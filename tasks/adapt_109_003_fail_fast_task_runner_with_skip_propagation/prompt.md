# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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
        # No task with all dependencies resolved => remaining tasks form/feed a cycle.
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

## New specification

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
