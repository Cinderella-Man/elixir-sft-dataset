# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `topological_layers` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Fail-Fast Task Runner with Skip Propagation

Write me an Elixir `GenServer` module called `ResilientRunner` that accepts tasks
with dependencies, executes them in a valid order running independent tasks
concurrently, and **handles task failures by skipping their dependents** instead
of crashing. A task's failure must not take down the runner or unrelated
branches — only the tasks that (transitively) depend on the failed task are
skipped.

## Public API

- `ResilientRunner.start_link(opts)` — starts the process. It must accept a
  `:name` option used for process registration. Return the usual `{:ok, pid}`.

- `ResilientRunner.submit(name, task_id, opts)` — registers a task.
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a zero-arity function to execute. Required.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Nothing runs until `run_all/1` is called.

- `ResilientRunner.run_all(name)` — validates the graph, then executes all tasks.
  - A task's `:func` runs only **after every one of its dependencies has finished
    executing**. Independent tasks that are all ready and do not depend on one
    another run **in parallel**.
  - A task **fails** if its `:func` returns `{:error, reason}` or raises/throws.
    Any other return value is a success, and that value is stored as the result.
  - When a task fails or is skipped, every task that depends on it (directly or
    transitively) is **skipped** — its `:func` is never invoked. Sibling branches
    that do not depend on the failed task must still run to completion.
  - On success (for the graph as a whole, regardless of individual task
    failures) it returns
    `{:ok, %{completed: completed, failed: failed, skipped: skipped}}` where:
    - `completed` is a map from `task_id` to the successful return value,
    - `failed` is a map from `task_id` to the failure reason (a raise/throw is
      captured, never re-raised),
    - `skipped` is a list of the `task_id`s that were never run because an
      upstream task failed or was itself skipped.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return `{:error, {:unknown_dependencies, missing}}`.
  - Calling `run_all/1` with no submitted tasks returns
    `{:ok, %{completed: %{}, failed: %{}, skipped: []}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering, real parallelism of independent
  ready tasks, and precise failure containment: a failure prunes exactly the
  downstream subgraph and nothing more.

## The module with `topological_layers` missing

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
    # TODO
  end

  defp build_layers(in_degree, _dependents, layers) when map_size(in_degree) == 0 do
    {:ok, Enum.reverse(layers)}
  end

  defp build_layers(in_degree, dependents, layers) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] ->
        {:error, {:cycle, Map.keys(in_degree)}}

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

Give me only the complete implementation of `topological_layers` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
