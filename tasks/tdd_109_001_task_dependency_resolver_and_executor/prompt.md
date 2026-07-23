# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
defmodule TaskRunnerTest do
  use ExUnit.Case, async: false

  # ------------------------------------------------------------------
  # Inline test helpers
  # ------------------------------------------------------------------

  # Records start/end events (with monotonic timestamps) for each task so we
  # can assert ordering and parallelism after run_all/1 returns.
  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(id, phase) do
      t = System.monotonic_time(:millisecond)
      Agent.update(__MODULE__, fn evs -> [{id, phase, t} | evs] end)
    end

    def events, do: Agent.get(__MODULE__, &Enum.reverse/1)

    def time(id, phase) do
      events()
      |> Enum.find_value(fn
        {^id, ^phase, t} -> t
        _ -> nil
      end)
    end

    def started_at(id), do: time(id, :start)
    def ended_at(id), do: time(id, :end)
  end

  # Builds a zero-arity task func that records its lifecycle, optionally sleeps,
  # and returns `ret`.
  defp task(id, sleep_ms \\ 0, ret \\ nil) do
    ret = if is_nil(ret), do: id, else: ret

    fn ->
      Recorder.record(id, :start)
      if sleep_ms > 0, do: Process.sleep(sleep_ms)
      Recorder.record(id, :end)
      ret
    end
  end

  setup do
    start_supervised!(Recorder)
    pid = start_supervised!({TaskRunner, name: :runner})
    %{runner: pid}
  end

  # ------------------------------------------------------------------
  # Basic execution / results
  # ------------------------------------------------------------------

  test "empty runner returns an empty result map" do
    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{}
  end

  test "runs a single task with no dependencies and returns its value" do
    assert :ok = TaskRunner.submit(:runner, :a, func: task(:a, 0, 42))

    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{a: 42}
  end

  test "results are keyed by task_id for a whole DAG" do
    TaskRunner.submit(:runner, :a, func: task(:a, 0, 1))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 0, 2))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 0, 3))
    TaskRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 0, 4))

    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{a: 1, b: 2, c: 3, d: 4}
  end

  # ------------------------------------------------------------------
  # Ordering respects dependencies
  # ------------------------------------------------------------------

  test "a dependent task starts only after its dependency has finished" do
    TaskRunner.submit(:runner, :a, func: task(:a, 50))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 10))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
  end

  test "a task waits for ALL of its dependencies (diamond DAG)" do
    #      a
    #     / \
    #    b   c
    #     \ /
    #      d
    TaskRunner.submit(:runner, :a, func: task(:a, 40))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 120))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 120))
    TaskRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 20))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    # b and c start only after a finishes
    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
    assert Recorder.ended_at(:a) <= Recorder.started_at(:c)

    # d starts only after BOTH b and c finish
    assert Recorder.ended_at(:b) <= Recorder.started_at(:d)
    assert Recorder.ended_at(:c) <= Recorder.started_at(:d)
  end

  test "long dependency chain executes strictly in order" do
    TaskRunner.submit(:runner, :t1, func: task(:t1, 10))
    TaskRunner.submit(:runner, :t2, depends_on: [:t1], func: task(:t2, 10))
    TaskRunner.submit(:runner, :t3, depends_on: [:t2], func: task(:t3, 10))
    TaskRunner.submit(:runner, :t4, depends_on: [:t3], func: task(:t4, 10))

    assert {:ok, %{t1: :t1, t2: :t2, t3: :t3, t4: :t4}} =
             TaskRunner.run_all(:runner)

    assert Recorder.ended_at(:t1) <= Recorder.started_at(:t2)
    assert Recorder.ended_at(:t2) <= Recorder.started_at(:t3)
    assert Recorder.ended_at(:t3) <= Recorder.started_at(:t4)
  end

  # ------------------------------------------------------------------
  # Independent tasks run in parallel
  # ------------------------------------------------------------------

  test "independent sibling tasks overlap in time" do
    TaskRunner.submit(:runner, :a, func: task(:a, 40))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 150))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 150))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    # Overlap test: each starts before the other ends.
    assert Recorder.started_at(:b) < Recorder.ended_at(:c)
    assert Recorder.started_at(:c) < Recorder.ended_at(:b)
  end

  test "a wide layer of independent tasks runs concurrently (wall-clock)" do
    for i <- 1..5 do
      id = :"job_#{i}"
      TaskRunner.submit(:runner, id, func: task(id, 120))
    end

    {elapsed_us, {:ok, results}} =
      :timer.tc(fn -> TaskRunner.run_all(:runner) end)

    elapsed_ms = div(elapsed_us, 1000)

    assert map_size(results) == 5
    # Sequential would be ~600ms; parallel should be far less.
    assert elapsed_ms < 400
    # Sanity: the tasks actually ran (didn't skip the sleep).
    assert elapsed_ms >= 100
  end

  # ------------------------------------------------------------------
  # Cycle detection
  # ------------------------------------------------------------------

  test "detects a direct two-node cycle and reports it" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, involved}} = TaskRunner.run_all(:runner)
    assert :a in involved
    assert :b in involved
  end

  test "a task that merely depends on a cycle is not reported as involved" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c))

    assert {:error, {:cycle, involved}} = TaskRunner.run_all(:runner)
    assert :a in involved
    assert :b in involved
    refute :c in involved
  end

  test "detects a larger cycle" do
    TaskRunner.submit(:runner, :a, depends_on: [:c], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))
    TaskRunner.submit(:runner, :c, depends_on: [:b], func: task(:c))

    assert {:error, {:cycle, _involved}} = TaskRunner.run_all(:runner)
  end

  test "a self-dependency is a cycle" do
    TaskRunner.submit(:runner, :a, depends_on: [:a], func: task(:a))

    assert {:error, {:cycle, _}} = TaskRunner.run_all(:runner)
  end

  test "no task executes when a cycle is present" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, _}} = TaskRunner.run_all(:runner)
    assert Recorder.events() == []
  end

  # ------------------------------------------------------------------
  # Unknown dependencies
  # ------------------------------------------------------------------

  test "reports a dependency that was never submitted" do
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} =
             TaskRunner.run_all(:runner)

    assert :a in missing
  end

  test "does not execute any task when a dependency is unknown" do
    TaskRunner.submit(:runner, :real, func: task(:real))
    TaskRunner.submit(:runner, :b, depends_on: [:ghost], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} =
             TaskRunner.run_all(:runner)

    assert :ghost in missing
    assert Recorder.events() == []
  end

  # ------------------------------------------------------------------
  # Re-submission
  # ------------------------------------------------------------------

  test "submitting the same task_id again overwrites the definition" do
    TaskRunner.submit(:runner, :a, func: task(:a, 0, :first))
    TaskRunner.submit(:runner, :a, func: task(:a, 0, :second))

    assert {:ok, %{a: :second}} = TaskRunner.run_all(:runner)
  end
end
```

Send back the implementation only — one file, no tests.
