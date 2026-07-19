# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Data-Flow Task Dependency Resolver

Write me an Elixir `GenServer` module called `DataFlowRunner` that accepts tasks
with dependencies and executes them in a valid order, running independent tasks
concurrently — **and threads each task's dependency results into that task's
function as input**. Unlike a plain runner where every function is zero-arity and
self-contained, here a task's function receives the outputs of the tasks it
depends on, so data flows down the DAG.

## Public API

- `DataFlowRunner.start_link(opts)` — starts the process. It must accept a `:name`
  option used for process registration (so the process can be referred to by an
  atom name in the other functions). Return the usual `{:ok, pid}`.

- `DataFlowRunner.submit(name, task_id, opts)` — registers a task with the runner.
  - `name` is the registered process name.
  - `task_id` is any term that uniquely identifies the task (typically an atom).
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a **one-arity** function. Required. It is called with a map
      `%{dep_id => result}` containing the return value of each of this task's
      **direct** dependencies. A task with no dependencies receives `%{}`.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Tasks are only *registered* by `submit/3`; nothing runs until
    `run_all/1` is called. If `:func` is not a one-arity function, raise
    `ArgumentError`.

- `DataFlowRunner.run_all(name)` — validates the dependency graph, then executes
  all submitted tasks.
  - It must perform a topological sort so that a task's `:func` only begins
    executing **after every one of its dependencies has finished executing**, and
    only then with those dependencies' results as its input map.
  - Tasks whose dependencies are all satisfied and that do not depend on one
    another must run **in parallel** (concurrently), not sequentially.
  - On success it returns `{:ok, results}` where `results` is a map from
    `task_id` to the value returned by that task's `:func`.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`, where `involved` is a list of
    the `task_id`s participating in a cycle.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return
    `{:error, {:unknown_dependencies, missing}}`, where `missing` is a list of
    the referenced-but-unknown `task_id`s.
  - Calling `run_all/1` on a runner with no submitted tasks returns `{:ok, %{}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering, real parallelism, *and* correct
  data flow: each function must observe exactly the results of the tasks it
  declared as dependencies.

## The module with `handle_call` missing

```elixir
defmodule DataFlowRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a
  valid topological order, running independent tasks concurrently, while
  threading each task's dependency results into that task's one-arity function.

  Execution proceeds layer by layer: every task in a layer has all of its
  dependencies satisfied and none of the tasks in the same layer depend on one
  another, so they run in parallel. Before a task runs, the results of its
  direct dependencies are collected into a map and passed as its single argument.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Starts the runner. Accepts a `:name` option used for process registration."
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec submit(GenServer.server(), term(), keyword()) :: :ok
  @doc "Submits `task_id` with its dependencies/opts to runner `name`. Returns `:ok`."
  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 1) ->
          f

        {:ok, _} ->
          raise ArgumentError, ":func must be a one-arity function"

        :error ->
          raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end

  @spec run_all(GenServer.server()) ::
          {:ok, map()}
          | {:error, {:cycle, [term()]}}
          | {:error, {:unknown_dependencies, [term()]}}
  @doc """
  Validates the dependency graph and executes every submitted task.

  Returns `{:ok, results}` on success, `{:error, {:cycle, involved}}` when the
  graph contains a cycle, or `{:error, {:unknown_dependencies, missing}}` when a
  task references a dependency that was never submitted. In both error cases no
  task is executed.
  """
  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(_), do: {:ok, %{}}

  def handle_call({:submit, task_id, depends_on, func}, _from, tasks) do
    # TODO
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
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

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
        {:error, {:cycle, cycle_nodes(Map.keys(in_degree), dependents)}}

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

  # ── Cycle extraction ────────────────────────────────────────────────────

  # The tasks left over when Kahn's algorithm stalls include both the tasks on a
  # cycle and their downstream dependents. Repeatedly dropping tasks that nothing
  # in the remaining set depends on leaves only the tasks on a cycle.
  defp cycle_nodes(ids, dependents) do
    ids |> MapSet.new() |> prune_downstream(dependents)
  end

  defp prune_downstream(set, dependents) do
    next =
      set
      |> Enum.filter(fn id ->
        dependents
        |> Map.get(id, [])
        |> Enum.any?(&MapSet.member?(set, &1))
      end)
      |> MapSet.new()

    if MapSet.size(next) == MapSet.size(set) do
      Enum.to_list(next)
    else
      prune_downstream(next, dependents)
    end
  end

  # ── Execution (data-flow: pass dependency results as input) ──────────────

  defp execute(layers, tasks) do
    Enum.reduce(layers, %{}, fn layer, results ->
      layer_results =
        layer
        |> Enum.map(fn id ->
          %{depends_on: deps, func: func} = Map.fetch!(tasks, id)
          inputs = Map.new(deps, fn d -> {d, Map.fetch!(results, d)} end)
          {id, Task.async(fn -> func.(inputs) end)}
        end)
        |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
        |> Map.new()

      Map.merge(results, layer_results)
    end)
  end
end
```

Give me only the complete implementation of `handle_call` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
