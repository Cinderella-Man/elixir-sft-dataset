# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule TaskRunner do
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
        {:ok, f} when is_function(f, 0) ->
          f

        {:ok, _} ->
          raise ArgumentError, ":func must be a zero-arity function"

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
