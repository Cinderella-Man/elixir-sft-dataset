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
end