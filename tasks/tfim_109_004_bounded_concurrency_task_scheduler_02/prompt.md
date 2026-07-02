# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BoundedRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a valid
  topological order, but runs at most `:max_concurrency` tasks simultaneously.

  Rather than executing whole dependency layers at once, it maintains a ready
  queue and a running set: it starts ready tasks up to the concurrency budget,
  waits for one to finish, releases that task's dependents (adding any that
  become ready), and repeats until every task has run.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    max = Keyword.get(opts, :max_concurrency, 4)

    unless is_integer(max) and max > 0 do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    GenServer.start_link(__MODULE__, max, name: name)
  end

  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 0) -> f
        {:ok, _} -> raise ArgumentError, ":func must be a zero-arity function"
        :error -> raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end

  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(max), do: {:ok, %{tasks: %{}, max: max}}

  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, state) do
    tasks = Map.put(state.tasks, task_id, %{depends_on: depends_on, func: func})
    {:reply, :ok, %{state | tasks: tasks}}
  end

  def handle_call(:run_all, _from, state) do
    tasks = state.tasks

    result =
      with :ok <- check_unknown_dependencies(tasks),
           :ok <- ensure_acyclic(tasks) do
        {:ok, schedule(tasks, state.max)}
      end

    {:reply, result, state}
  end

  # ── Validation ──────────────────────────────────────────────────────────

  defp check_unknown_dependencies(tasks) do
    known = MapSet.new(Map.keys(tasks))

    missing =
      tasks
      |> Enum.flat_map(fn {_id, %{depends_on: deps}} -> deps end)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(known, &1))

    case missing do
      [] -> :ok
      _ -> {:error, {:unknown_dependencies, missing}}
    end
  end

  # Detect cycles up front (Kahn) so no task runs when the graph is invalid.
  defp ensure_acyclic(tasks) do
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    dependents = build_dependents(tasks)
    strip(in_degree, dependents)
  end

  defp strip(in_degree, _dependents) when map_size(in_degree) == 0, do: :ok

  defp strip(in_degree, dependents) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] ->
        {:error, {:cycle, Map.keys(in_degree)}}

      _ ->
        remaining = Map.drop(in_degree, ready)
        remaining = decrement_dependents(ready, remaining, dependents)
        strip(remaining, dependents)
    end
  end

  # ── Bounded scheduler ─────────────────────────────────────────────────────

  defp schedule(tasks, max) when map_size(tasks) == 0 and max > 0, do: %{}

  defp schedule(tasks, max) do
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    dependents = build_dependents(tasks)
    ready = for {id, 0} <- in_degree, do: id

    loop(%{
      tasks: tasks,
      max: max,
      in_degree: in_degree,
      dependents: dependents,
      ready: ready,
      running: %{},
      results: %{}
    })
  end

  defp loop(s) do
    running_count = map_size(s.running)

    cond do
      s.ready != [] and running_count < s.max ->
        [id | rest] = s.ready
        %{func: func} = Map.fetch!(s.tasks, id)
        task = Task.async(fn -> func.() end)
        loop(%{s | ready: rest, running: Map.put(s.running, task.ref, id)})

      running_count == 0 and s.ready == [] ->
        s.results

      true ->
        loop(await_one(s))
    end
  end

  defp await_one(s) do
    receive do
      {ref, value} when is_map_key(s.running, ref) ->
        Process.demonitor(ref, [:flush])
        id = Map.fetch!(s.running, ref)
        running = Map.delete(s.running, ref)
        results = Map.put(s.results, id, value)

        {in_degree, newly_ready} =
          s.dependents
          |> Map.get(id, [])
          |> Enum.reduce({s.in_degree, []}, fn dep, {ind, acc} ->
            case Map.fetch(ind, dep) do
              {:ok, n} ->
                nn = n - 1
                acc = if nn == 0, do: [dep | acc], else: acc
                {Map.put(ind, dep, nn), acc}

              :error ->
                {ind, acc}
            end
          end)

        %{
          s
          | running: running,
            results: results,
            in_degree: in_degree,
            ready: s.ready ++ Enum.reverse(newly_ready)
        }
    end
  end

  # ── Shared helpers ────────────────────────────────────────────────────────

  defp build_dependents(tasks) do
    Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
      Enum.reduce(Enum.uniq(deps), acc, fn dep, acc2 ->
        Map.update(acc2, dep, [id], &[id | &1])
      end)
    end)
  end

  defp decrement_dependents(ids, in_degree, dependents) do
    Enum.reduce(ids, in_degree, fn id, acc ->
      dependents
      |> Map.get(id, [])
      |> Enum.reduce(acc, fn dependent, acc2 ->
        case Map.fetch(acc2, dependent) do
          {:ok, n} -> Map.put(acc2, dependent, n - 1)
          :error -> acc2
        end
      end)
    end)
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
```
