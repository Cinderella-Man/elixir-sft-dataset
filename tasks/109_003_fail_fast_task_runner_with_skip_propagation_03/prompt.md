# Fill-in-the-middle: `build_layers/3`

The module below is a complete implementation of `ResilientRunner` — a
`GenServer` that runs dependency-ordered tasks with failure containment — **except**
for the private helper `build_layers/3`, whose two clause bodies have been replaced
with `# TODO`.

Implement the private `build_layers/3` function. It is the recursive core of a
topological sort (Kahn's algorithm) that groups tasks into **layers**, where each
layer is a set of tasks whose dependencies have all been satisfied by earlier
layers, so the tasks within a layer can run in parallel.

It receives three arguments:

- `in_degree` — a map from `task_id` to the number of its dependencies that have
  not yet been placed into a layer.
- `dependents` — a map from `task_id` to the list of tasks that directly depend on
  it (the reverse edges).
- `layers` — an accumulator holding the layers discovered so far, in **reverse**
  order (most recent layer first).

Behavior:

- **Base case:** when `in_degree` is empty (`map_size(in_degree) == 0`), every task
  has been placed. Return `{:ok, layers}` with the accumulated layers put back into
  the correct order (i.e. reverse the accumulator).
- **Recursive case:** compute `ready`, the list of task ids whose `in_degree` is
  `0`.
  - If `ready` is empty while tasks still remain, the graph has a cycle — return
    `{:error, {:cycle, involved}}` where `involved` is the list of the still-remaining
    task ids (`Map.keys(in_degree)`).
  - Otherwise, drop all `ready` ids from `in_degree`, and for each `ready` id
    decrement the `in_degree` of every task that depends on it (look each up in
    `dependents`, skipping any that are no longer present). Then recurse with the
    updated `in_degree`, the same `dependents`, and `ready` prepended to `layers`.

```elixir
defmodule ResilientRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a valid
  topological order, running independent ready tasks concurrently, while
  containing failures: a task that returns `{:error, reason}` or raises/throws is
  recorded as failed (never re-raised), and every task that transitively depends
  on it is skipped. Sibling branches that don't depend on the failed task still
  run to completion.
  """

  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec submit(GenServer.server(), term(), keyword()) :: :ok | {:error, atom()}
  @doc "Submits `task_id` with its dependencies/opts to runner `name`. Returns `:ok`."
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

  # ── Execution with failure containment ──────────────────────────────────

  defp execute(layers, tasks) do
    init = %{completed: %{}, failed: %{}, skipped: MapSet.new()}

    final =
      Enum.reduce(layers, init, fn layer, acc ->
        {to_skip, to_run} =
          Enum.split_with(layer, fn id ->
            %{depends_on: deps} = Map.fetch!(tasks, id)

            Enum.any?(deps, fn d ->
              Map.has_key?(acc.failed, d) or MapSet.member?(acc.skipped, d)
            end)
          end)

        acc =
          Enum.reduce(to_skip, acc, fn id, a ->
            %{a | skipped: MapSet.put(a.skipped, id)}
          end)

        to_run
        |> Enum.map(fn id ->
          %{func: func} = Map.fetch!(tasks, id)
          {id, Task.async(fn -> run_task(func) end)}
        end)
        |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
        |> Enum.reduce(acc, fn {id, outcome}, a ->
          case outcome do
            {:ok, value} -> %{a | completed: Map.put(a.completed, id, value)}
            {:failed, reason} -> %{a | failed: Map.put(a.failed, id, reason)}
          end
        end)
      end)

    %{final | skipped: MapSet.to_list(final.skipped)}
  end

  defp run_task(func) do
    try do
      case func.() do
        {:error, reason} -> {:failed, reason}
        other -> {:ok, other}
      end
    rescue
      e -> {:failed, {:exception, e}}
    catch
      kind, value -> {:failed, {kind, value}}
    end
  end
end

```