# Fill in the middle: `build_layers/3`

Below is a complete `DataFlowRunner` GenServer module, except that the private
helper `build_layers/3` has had its body removed. Implement `build_layers/3` so
that the rest of the module works.

## What `build_layers/3` must do

`build_layers/3` is the engine of a layer-grouped topological sort (Kahn's
algorithm). It is called from `topological_layers/1` with:

- `in_degree` — a map from `task_id` to the number of (unique) dependencies that
  have **not yet** been placed into a layer.
- `dependents` — a map from `task_id` to the list of tasks that depend on it
  (the reverse edges of the DAG).
- `layers` — the accumulator: a list of already-built layers, in **reverse**
  order (most recently built layer first).

It must return either `{:ok, layers}` (layers in correct forward order, each
layer being a list of `task_id`s) or `{:error, {:cycle, involved}}`.

Implement it as two clauses:

1. **Base case** — when `in_degree` is empty (`map_size(in_degree) == 0`), every
   task has been assigned to a layer. Return `{:ok, layers}` with the accumulated
   layers reversed back into forward order.

2. **Recursive case** — otherwise:
   - Compute `ready`, the list of task ids whose current in-degree is `0`. These
     are the tasks that can run in this layer.
   - If `ready` is empty while tasks still remain, no progress can be made, which
     means the remaining tasks form a cycle. Return
     `{:error, {:cycle, Map.keys(in_degree)}}`.
   - Otherwise, remove the `ready` tasks from `in_degree`, and for each dependent
     of a ready task, decrement its in-degree by 1 (skipping any dependent that
     is no longer present in the remaining map). Then recurse with the updated
     in-degree map and `ready` prepended to `layers`.

## Module (implement the `# TODO` in `build_layers/3`)

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

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

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
    # TODO
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