# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ResilientRunnerTest do
  use ExUnit.Case, async: false

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

    def ran?(id) do
      Enum.any?(events(), fn
        {^id, :start, _} -> true
        _ -> false
      end)
    end
  end

  defp ok_task(id, sleep_ms \\ 0, ret \\ nil) do
    ret = if is_nil(ret), do: id, else: ret

    fn ->
      Recorder.record(id, :start)
      if sleep_ms > 0, do: Process.sleep(sleep_ms)
      Recorder.record(id, :end)
      ret
    end
  end

  defp fail_task(id, reason \\ :boom) do
    fn ->
      Recorder.record(id, :start)
      Recorder.record(id, :end)
      {:error, reason}
    end
  end

  defp raise_task(id) do
    fn ->
      Recorder.record(id, :start)
      raise "boom-#{id}"
    end
  end

  # A task that announces itself and then blocks until the test releases it.
  # Two such tasks can only both announce if they are in flight at the same
  # moment; a runner that finishes one task before starting the next can never
  # produce the second announcement while the first is still blocked.
  defp gate_task(id, test_pid, ret) do
    fn ->
      Recorder.record(id, :start)
      send(test_pid, {:running, id, self()})

      result =
        receive do
          :release -> ret
        after
          5_000 -> {:error, :never_released}
        end

      Recorder.record(id, :end)
      result
    end
  end

  setup do
    start_supervised!(Recorder)
    pid = start_supervised!({ResilientRunner, name: :runner})
    %{runner: pid}
  end

  test "empty runner returns empty completed/failed/skipped" do
    assert {:ok, %{completed: %{}, failed: %{}, skipped: []}} =
             ResilientRunner.run_all(:runner)
  end

  test "all-success DAG populates completed" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, 1))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 0, 2))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, 3))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: 1, b: 2, c: 3}
    assert res.failed == %{}
    assert res.skipped == []
  end

  test "an {:error, _} return marks failure and skips dependents" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a, :db_down))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.failed == %{a: :db_down}
    assert res.skipped == [:b]
    assert res.completed == %{}
    refute Recorder.ran?(:b)
  end

  test "a raising task is captured as a failure, not re-raised" do
    ResilientRunner.submit(:runner, :a, func: raise_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
    refute Recorder.ran?(:b)
  end

  test "skip propagates transitively down a chain" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:b], func: ok_task(:c))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert Enum.sort(res.skipped) == [:b, :c]
    refute Recorder.ran?(:b)
    refute Recorder.ran?(:c)
  end

  test "an unrelated sibling branch still completes when another fails" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :x, func: ok_task(:x, 0, :x_val))
    ResilientRunner.submit(:runner, :y, depends_on: [:x], func: ok_task(:y, 0, :y_val))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{x: :x_val, y: :y_val}
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
  end

  test "diamond: one failing parent skips only the join, other parent completes" do
    #      a
    #     / \
    #    b   c    (b fails)
    #     \ /
    #      d
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: fail_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, :c))
    ResilientRunner.submit(:runner, :d, depends_on: [:b, :c], func: ok_task(:d))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: :a, c: :c}
    assert Map.has_key?(res.failed, :b)
    assert res.skipped == [:d]
    refute Recorder.ran?(:d)
  end

  test "a dependent starts only after its dependency finishes" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 50))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 10))

    assert {:ok, _} = ResilientRunner.run_all(:runner)

    a_end =
      Enum.find_value(Recorder.events(), fn
        {:a, :end, t} -> t
        _ -> nil
      end)

    b_start =
      Enum.find_value(Recorder.events(), fn
        {:b, :start, t} -> t
        _ -> nil
      end)

    assert a_end <= b_start
  end

  test "detects a cycle and runs nothing" do
    ResilientRunner.submit(:runner, :a, depends_on: [:b], func: ok_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:error, {:cycle, involved}} = ResilientRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Recorder.events() == []
  end

  test "reports unknown dependencies and runs nothing" do
    ResilientRunner.submit(:runner, :b, depends_on: [:ghost], func: ok_task(:b))

    assert {:error, {:unknown_dependencies, missing}} = ResilientRunner.run_all(:runner)
    assert :ghost in missing
    assert Recorder.events() == []
  end

  test "resubmitting a task overwrites its definition" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :first))
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :second))

    assert {:ok, %{completed: %{a: :second}}} = ResilientRunner.run_all(:runner)
  end

  test "two independent tasks are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :p, func: gate_task(:p, me, :p_val))
    ResilientRunner.submit(:runner, :q, func: gate_task(:q, me, :q_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Both must announce while neither has been released: a runner that
    # executes independent tasks one after the other cannot get here.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:p, :q]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{p: :p_val, q: :q_val}
    assert res.failed == %{}
    assert res.skipped == []
  end

  test "siblings sharing a dependency are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :root, func: ok_task(:root, 0, :root_val))
    ResilientRunner.submit(:runner, :b, depends_on: [:root], func: gate_task(:b, me, :b_val))
    ResilientRunner.submit(:runner, :c, depends_on: [:root], func: gate_task(:c, me, :c_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Once their shared dependency has finished, both dependents become ready
    # and must overlap rather than take turns.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:b, :c]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{root: :root_val, b: :b_val, c: :c_val}
    assert res.failed == %{}
    assert res.skipped == []
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
