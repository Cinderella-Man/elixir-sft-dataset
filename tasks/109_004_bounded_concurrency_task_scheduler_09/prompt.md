# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Bounded-Concurrency Task Scheduler

Write me an Elixir `GenServer` module called `BoundedRunner` that accepts tasks
with dependencies and executes them in a valid order — but runs **at most
`max_concurrency` tasks at any instant**, even when far more tasks are ready.
Ready tasks beyond the concurrency budget wait for a running slot to free up.

## Public API

- `BoundedRunner.start_link(opts)` — starts the process. It must accept:
  - `:name` — used for process registration.
  - `:max_concurrency` — a positive integer bounding how many tasks may run
    simultaneously. Optional, defaults to `4`. A non-positive or non-integer
    value must raise `ArgumentError`.
  Return the usual `{:ok, pid}`.

- `BoundedRunner.submit(name, task_id, opts)` — registers a task.
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a zero-arity function to execute. Required.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Nothing runs until `run_all/1` is called.

- `BoundedRunner.run_all(name)` — validates the graph, then executes all tasks.
  - A task's `:func` runs only **after every one of its dependencies has finished
    executing**.
  - At no point may more than `max_concurrency` tasks be executing at once. When
    more tasks are ready than there are free slots, the extras wait; as each
    running task finishes, a free slot is immediately given to a waiting ready
    task (and finishing a task may make new tasks ready by satisfying their
    dependencies).
  - On success it returns `{:ok, results}` where `results` maps each `task_id`
    to the value returned by its `:func`.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`, where `involved` is a list
    of `task_id`s that includes those participating in the cycle.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return `{:error, {:unknown_dependencies, missing}}`,
    where `missing` is a list containing the dependency `task_id`s that were
    never submitted.
  - Calling `run_all/1` with no submitted tasks returns `{:ok, %{}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering *and* a hard concurrency ceiling:
  with `max_concurrency: 2`, six independent equal-length tasks should take
  roughly three waves, not one; and dependency ordering must still hold exactly.

## The module with `handle_call` missing

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

  def handle_call({:submit, task_id, depends_on, func}, _from, state) do
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

Give me only the complete implementation of `handle_call` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
