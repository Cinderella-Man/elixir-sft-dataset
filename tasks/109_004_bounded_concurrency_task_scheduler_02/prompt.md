# Implement `loop/1`

`loop/1` is the private, recursive heart of the bounded scheduler. It receives a
single state map `s` with these keys:

- `:tasks` — map of `task_id => %{depends_on: [...], func: fun}`.
- `:max` — the concurrency ceiling (a positive integer).
- `:in_degree` — map of `task_id => remaining unsatisfied dependency count`.
- `:dependents` — map of `task_id => [ids that depend on it]`.
- `:ready` — a list of `task_id`s whose dependencies are all satisfied and that
  have not yet been started.
- `:running` — map of `Task` monitor `ref => task_id` for tasks currently
  executing.
- `:results` — map of `task_id => value` for tasks that have finished.

Implement `loop/1` so that it drives the schedule to completion and returns the
final `:results` map. It must decide what to do next based on the current state,
respecting the hard concurrency ceiling. There are exactly three cases:

1. **A slot is free and work is waiting** — when `:ready` is non-empty *and* the
   number of running tasks (`map_size(s.running)`) is below `:max`: pop the first
   `task_id` off `:ready`, look up its `:func` in `:tasks`, start it with
   `Task.async/1` (invoking the zero-arity `func`), record the new task in
   `:running` keyed by the `Task`'s `ref` (mapping to the `task_id`), and recurse
   on the updated state. This is what enforces the ceiling: no new task is started
   once `:running` is at `:max`.

2. **Everything is done** — when there are no running tasks *and* nothing is
   ready (`running_count == 0` and `:ready == []`): return `s.results`.

3. **Otherwise** — the ceiling is reached (or nothing is ready but tasks are still
   running): wait for exactly one running task to finish by calling `await_one/1`,
   then recurse on the state it returns. (`await_one/1` removes the finished task
   from `:running`, records its result, decrements its dependents' in-degrees, and
   appends any newly-ready tasks to `:ready`.)

Order the branches so that starting ready work is preferred while a slot is free,
then the termination check, then waiting.

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
    # TODO
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