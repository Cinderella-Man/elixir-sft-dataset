# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule BoundedRunnerTest do
  use ExUnit.Case, async: false

  # Tracks lifecycle events and a concurrency high-water mark. All updates run
  # inside the agent so the running count and max are consistent.
  defmodule Tracker do
    use Agent

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> %{events: [], current: 0, max: 0} end, name: __MODULE__)
    end

    def enter(id) do
      Agent.update(__MODULE__, fn s ->
        nc = s.current + 1
        %{s | current: nc, max: max(s.max, nc), events: [{id, :start, mono()} | s.events]}
      end)
    end

    def leave(id) do
      Agent.update(__MODULE__, fn s ->
        %{s | current: s.current - 1, events: [{id, :end, mono()} | s.events]}
      end)
    end

    defp mono, do: System.monotonic_time(:millisecond)

    def max_seen, do: Agent.get(__MODULE__, & &1.max)
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1.events))

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

  defp task(id, sleep_ms \\ 0, ret \\ nil) do
    ret = if is_nil(ret), do: id, else: ret

    fn ->
      Tracker.enter(id)
      if sleep_ms > 0, do: Process.sleep(sleep_ms)
      Tracker.leave(id)
      ret
    end
  end

  setup do
    start_supervised!(Tracker)
    :ok
  end

  defp start_runner(max) do
    start_supervised!({BoundedRunner, name: :runner, max_concurrency: max})
  end

  test "empty runner returns an empty map" do
    start_runner(2)
    assert {:ok, %{}} = BoundedRunner.run_all(:runner)
  end

  test "single task returns its value" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, 42))
    assert {:ok, %{a: 42}} = BoundedRunner.run_all(:runner)
  end

  test "concurrency never exceeds max even with many ready tasks" do
    start_runner(2)

    for i <- 1..6 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 60))
    end

    assert {:ok, results} = BoundedRunner.run_all(:runner)
    assert map_size(results) == 6
    assert Tracker.max_seen() <= 2
  end

  test "with max_concurrency 1 execution is fully serial" do
    start_runner(1)

    for i <- 1..4 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 20))
    end

    assert {:ok, results} = BoundedRunner.run_all(:runner)
    assert map_size(results) == 4
    assert Tracker.max_seen() == 1
  end

  test "bounded runner takes multiple waves (wall clock)" do
    start_runner(2)

    for i <- 1..6 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 80))
    end

    {elapsed_us, {:ok, _}} = :timer.tc(fn -> BoundedRunner.run_all(:runner) end)
    elapsed_ms = div(elapsed_us, 1000)

    # 6 tasks, 2 at a time, 80ms each => ~3 waves => >= ~240ms.
    assert elapsed_ms >= 200
  end

  test "a high budget lets independent tasks overlap" do
    start_runner(8)
    BoundedRunner.submit(:runner, :a, func: task(:a, 100))
    BoundedRunner.submit(:runner, :b, func: task(:b, 100))
    BoundedRunner.submit(:runner, :c, func: task(:c, 100))

    assert {:ok, _} = BoundedRunner.run_all(:runner)
    assert Tracker.max_seen() == 3
  end

  test "dependency ordering is respected under a concurrency cap" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 40))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 10))

    assert {:ok, _} = BoundedRunner.run_all(:runner)
    assert Tracker.ended_at(:a) <= Tracker.started_at(:b)
  end

  test "diamond DAG produces correct results with a cap" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, 1))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 0, 2))
    BoundedRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 0, 3))
    BoundedRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 0, 4))

    assert {:ok, %{a: 1, b: 2, c: 3, d: 4}} = BoundedRunner.run_all(:runner)
    assert Tracker.ended_at(:b) <= Tracker.started_at(:d)
    assert Tracker.ended_at(:c) <= Tracker.started_at(:d)
  end

  test "detects a cycle and runs nothing" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, involved}} = BoundedRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Tracker.events() == []
  end

  test "reports unknown dependencies and runs nothing" do
    start_runner(2)
    BoundedRunner.submit(:runner, :b, depends_on: [:ghost], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} = BoundedRunner.run_all(:runner)
    assert :ghost in missing
    assert Tracker.events() == []
  end

  test "resubmitting a task overwrites its definition" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, :first))
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, :second))

    assert {:ok, %{a: :second}} = BoundedRunner.run_all(:runner)
  end

  test "invalid max_concurrency raises" do
    assert_raise ArgumentError, fn ->
      BoundedRunner.start_link(name: :bad, max_concurrency: 0)
    end
  end

  test "default max_concurrency admits four tasks at once but not a fifth" do
    parent = self()
    start_supervised!({BoundedRunner, name: :default_runner})

    for i <- 1..5 do
      id = :"d#{i}"

      BoundedRunner.submit(:default_runner, id,
        func: fn ->
          send(parent, {:started, id, self()})

          receive do
            :go -> id
          end
        end
      )
    end

    runner = Task.async(fn -> BoundedRunner.run_all(:default_runner) end)

    pids =
      for _ <- 1..4 do
        assert_receive {:started, _id, pid}, 500
        pid
      end

    refute_receive {:started, _, _}, 200

    Enum.each(pids, &send(&1, :go))
    assert_receive {:started, _id, fifth}, 500
    send(fifth, :go)

    assert {:ok, results} = Task.await(runner, 2000)
    assert map_size(results) == 5
  end

  test "a finishing task hands its slot to a waiting ready task" do
    parent = self()
    start_runner(2)

    for i <- 1..3 do
      id = :"slot_#{i}"

      BoundedRunner.submit(:runner, id,
        func: fn ->
          send(parent, {:started, id, self()})

          receive do
            :go -> id
          end
        end
      )
    end

    runner = Task.async(fn -> BoundedRunner.run_all(:runner) end)

    assert_receive {:started, _, first}, 500
    assert_receive {:started, _, second}, 500
    refute_receive {:started, _, _}, 200

    send(first, :go)
    assert_receive {:started, _, third}, 500

    send(second, :go)
    send(third, :go)

    assert {:ok, results} = Task.await(runner, 2000)
    assert map_size(results) == 3
  end

  test "submitting alone never executes a task func" do
    parent = self()
    start_runner(2)

    BoundedRunner.submit(:runner, :lazy,
      func: fn ->
        send(parent, :ran)
        :done
      end
    )

    refute_receive :ran, 300
    assert Tracker.events() == []

    assert {:ok, %{lazy: :done}} = BoundedRunner.run_all(:runner)
    assert_receive :ran, 500
  end

  test "non-integer max_concurrency raises" do
    assert_raise ArgumentError, fn ->
      BoundedRunner.start_link(name: :bad_float, max_concurrency: 2.0)
    end
  end

  test "a cycle prevents even independent tasks from running" do
    start_runner(2)
    BoundedRunner.submit(:runner, :free, func: task(:free))
    BoundedRunner.submit(:runner, :x, depends_on: [:y], func: task(:x))
    BoundedRunner.submit(:runner, :y, depends_on: [:x], func: task(:y))

    assert {:error, {:cycle, involved}} = BoundedRunner.run_all(:runner)
    assert :x in involved and :y in involved
    assert Tracker.events() == []
  end

  test "resubmitting replaces the previous dependency list" do
    start_runner(2)
    BoundedRunner.submit(:runner, :solo, depends_on: [:ghost], func: task(:solo, 0, :one))
    BoundedRunner.submit(:runner, :solo, func: task(:solo, 0, :two))

    assert {:ok, %{solo: :two}} = BoundedRunner.run_all(:runner)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
