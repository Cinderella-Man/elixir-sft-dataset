# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule TaskRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a
  valid topological order, running independent tasks concurrently.

  Tasks are registered with `submit/3` and only executed once `run_all/1` is
  called. Execution proceeds layer by layer: every task in a layer has all of
  its dependencies satisfied and none of the tasks in the same layer depend on
  one another, so they are run in parallel. As a result a wide layer of
  independent tasks takes roughly as long as the single slowest task in that
  layer.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Starts the runner.

  Accepts a `:name` option used for process registration so the process can be
  referred to by an atom name in the other functions.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Registers a task with the runner.

  `opts` is a keyword list with:

    * `:depends_on` — list of `task_id`s this task depends on (default `[]`).
    * `:func` — a zero-arity function to execute (required).

  Submitting the same `task_id` again overwrites the previous definition.
  Returns `:ok`.
  """
  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 0) ->
          f

        {:ok, _} ->
          raise ArgumentError, ":func must be a zero-arity function"

        :error ->
          raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end

  @doc """
  Validates the dependency graph and executes all submitted tasks.

  Returns `{:ok, results}` on success, where `results` maps each `task_id` to
  the value returned by its `:func`.

  Returns `{:error, {:unknown_dependencies, missing}}` if any task depends on a
  `task_id` that was never submitted, and `{:error, {:cycle, involved}}` if the
  graph contains a cycle. In both error cases no task is executed.
  """
  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(_state) do
    # state is a map: task_id => %{depends_on: [...], func: fun}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, tasks) do
    tasks = Map.put(tasks, task_id, %{depends_on: depends_on, func: func})
    {:reply, :ok, tasks}
  end

  @impl true
  def handle_call(:run_all, _from, tasks) do
    result =
      with :ok <- check_unknown_dependencies(tasks),
           {:ok, layers} <- topological_layers(tasks) do
        {:ok, execute(layers, tasks)}
      end

    {:reply, result, tasks}
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

  # ── Topological sort (Kahn's algorithm), grouped into layers ────────────

  defp topological_layers(tasks) do
    # in_degree: how many dependencies each task is still waiting on.
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    # dependents: for a dependency, which tasks depend on it.
    dependents =
      Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
        Enum.reduce(Enum.uniq(deps), acc, fn dep, acc2 ->
          Map.update(acc2, dep, [id], &[id | &1])
        end)
      end)

    build_layers(in_degree, dependents, [])
  end

  defp build_layers(in_degree, _dependents, layers) when map_size(in_degree) == 0 do
    {:ok, Enum.reverse(layers)}
  end

  defp build_layers(in_degree, dependents, layers) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] ->
        # No task with all dependencies resolved: the remaining tasks form or
        # feed a cycle. Report only the PARTICIPANTS — iteratively trim nodes
        # that nothing in the stuck set depends on; those merely sit
        # downstream of a cycle and are not part of one.
        {:error, {:cycle, cycle_members(in_degree, dependents)}}

      _ ->
        remaining = Map.drop(in_degree, ready)

        remaining =
          Enum.reduce(ready, remaining, fn id, acc ->
            dependents
            |> Map.get(id, [])
            |> Enum.reduce(acc, fn dependent, acc2 ->
              case Map.fetch(acc2, dependent) do
                {:ok, n} -> Map.put(acc2, dependent, n - 1)
                :error -> acc2
              end
            end)
          end)

        build_layers(remaining, dependents, [ready | layers])
    end
  end

  # A stuck node that nothing in the stuck set depends on cannot be part of
  # any cycle (every cycle member has a dependent inside the cycle) — it only
  # feeds on one. Trimming such nodes to a fixed point leaves exactly the
  # cycle participants.
  defp cycle_members(in_degree, dependents) do
    trim_feeders(MapSet.new(Map.keys(in_degree)), dependents)
  end

  defp trim_feeders(stuck, dependents) do
    feeders =
      Enum.filter(stuck, fn id ->
        dependents |> Map.get(id, []) |> Enum.all?(&(not MapSet.member?(stuck, &1)))
      end)

    case feeders do
      [] -> stuck |> MapSet.to_list() |> Enum.sort()
      _ -> trim_feeders(MapSet.difference(stuck, MapSet.new(feeders)), dependents)
    end
  end

  # ── Execution ───────────────────────────────────────────────────────────

  defp execute(layers, tasks) do
    Enum.reduce(layers, %{}, fn layer, results ->
      layer_results =
        layer
        |> Enum.map(fn id ->
          %{func: func} = Map.fetch!(tasks, id)
          {id, Task.async(func)}
        end)
        |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
        |> Map.new()

      Map.merge(results, layer_results)
    end)
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
