# Fill in the middle: `topological_layers/1`

Below is the complete `DataFlowRunner` module with the body of the private
function `topological_layers/1` removed. Implement it.

## What `topological_layers/1` must do

`topological_layers(tasks)` receives the `tasks` map held in the GenServer
state, where each entry is `task_id => %{depends_on: deps, func: fun}`. It must
perform a topological sort of the dependency graph and group the result into
**layers** — a list of lists of `task_id`s — such that every task in a layer has
all of its dependencies satisfied by earlier layers, and no two tasks in the
same layer depend on one another (so each layer can be run in parallel).

Do the setup work and delegate the actual layering to the provided
`build_layers/3` helper (Kahn's algorithm):

- Build an `in_degree` map from each `task_id` to the number of its **distinct**
  dependencies (deduplicate `deps` with `Enum.uniq/1` before counting).
- Build a `dependents` map (the reverse edges): for each `task_id`, for each of
  its distinct dependencies `dep`, record that `task_id` is a dependent of `dep`
  (i.e. `dep => [task_id, ...]`).
- Call `build_layers(in_degree, dependents, [])` and return its result.

On success it returns `{:ok, layers}`; if the graph contains a cycle,
`build_layers/3` returns `{:error, {:cycle, involved}}`, which you simply
propagate.

## Module

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

  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, tasks) do
    {:reply, :ok, Map.put(tasks, task_id, %{depends_on: depends_on, func: func})}
  end

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
    # TODO
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