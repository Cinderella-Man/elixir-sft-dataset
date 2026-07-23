# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule BoundedRunner do
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
