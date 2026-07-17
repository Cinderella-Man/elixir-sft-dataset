defmodule ResilientRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a valid
  dependency order, starting each task as soon as *its own* dependencies have
  finished (so independent branches never wait on one another), while containing
  failures: a task that returns `{:error, reason}` or raises/throws is recorded as
  failed (never re-raised), and every task that transitively depends on it is
  skipped. Sibling branches that don't depend on the failed task still run to
  completion.
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
        {:ok, f} when is_function(f, 0) -> f
        {:ok, _} -> raise ArgumentError, ":func must be a zero-arity function"
        :error -> raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end

  @spec run_all(GenServer.server()) ::
          {:ok, %{completed: map(), failed: map(), skipped: [term()]}}
          | {:error, {:cycle, [term()]} | {:unknown_dependencies, [term()]}}
  @doc """
  Validates the submitted graph and executes it, returning
  `{:ok, %{completed: map, failed: map, skipped: list}}`, or an error tuple when
  the graph has a cycle or references unknown dependencies (nothing runs then).
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
           :ok <- check_acyclic(tasks) do
        {:ok, execute(tasks)}
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

  # Kahn's algorithm, used purely to detect cycles before anything executes.
  defp check_acyclic(tasks) do
    in_degree =
      Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)

    dependents =
      Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
        Enum.reduce(Enum.uniq(deps), acc, fn dep, acc2 ->
          Map.update(acc2, dep, [id], &[id | &1])
        end)
      end)

    peel(in_degree, dependents)
  end

  defp peel(in_degree, _dependents) when map_size(in_degree) == 0, do: :ok

  defp peel(in_degree, dependents) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] ->
        {:error, {:cycle, Map.keys(in_degree)}}

      _ ->
        remaining =
          Enum.reduce(ready, Map.drop(in_degree, ready), fn id, acc ->
            dependents
            |> Map.get(id, [])
            |> Enum.reduce(acc, fn dependent, acc2 ->
              case Map.fetch(acc2, dependent) do
                {:ok, n} -> Map.put(acc2, dependent, n - 1)
                :error -> acc2
              end
            end)
          end)

        peel(remaining, dependents)
    end
  end

  # ── Execution with failure containment ──────────────────────────────────

  defp execute(tasks) do
    pending = Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, Enum.uniq(deps)} end)
    state = %{completed: %{}, failed: %{}, skipped: MapSet.new()}
    final = schedule(pending, %{}, state, tasks)
    %{final | skipped: MapSet.to_list(final.skipped)}
  end

  # Event-driven loop: start every task whose dependencies are all done, then wait
  # for the next completion and re-evaluate. A long-running task therefore never
  # delays an unrelated task that has just become ready.
  defp schedule(pending, running, state, tasks) do
    {pending, state} = propagate_skips(pending, state)

    {ready, still_pending} =
      Enum.split_with(pending, fn {_id, deps} ->
        Enum.all?(deps, &Map.has_key?(state.completed, &1))
      end)

    pending = Map.new(still_pending)

    running =
      Enum.reduce(ready, running, fn {id, _deps}, acc ->
        %{func: func} = Map.fetch!(tasks, id)
        task = Task.async(fn -> run_task(func) end)
        Map.put(acc, task.ref, id)
      end)

    cond do
      map_size(running) > 0 ->
        {running, state} = await_one(running, state)
        schedule(pending, running, state, tasks)

      map_size(pending) > 0 ->
        # Defensive: a validated DAG always yields progress, but never spin.
        Enum.reduce(pending, state, fn {id, _deps}, acc ->
          %{acc | skipped: MapSet.put(acc.skipped, id)}
        end)

      true ->
        state
    end
  end

  defp propagate_skips(pending, state) do
    {to_skip, keep} =
      Enum.split_with(pending, fn {_id, deps} ->
        Enum.any?(deps, fn d ->
          Map.has_key?(state.failed, d) or MapSet.member?(state.skipped, d)
        end)
      end)

    case to_skip do
      [] ->
        {Map.new(keep), state}

      _ ->
        state =
          Enum.reduce(to_skip, state, fn {id, _deps}, acc ->
            %{acc | skipped: MapSet.put(acc.skipped, id)}
          end)

        propagate_skips(Map.new(keep), state)
    end
  end

  defp await_one(running, state) do
    receive do
      {ref, outcome} when is_map_key(running, ref) ->
        Process.demonitor(ref, [:flush])
        record(running, ref, outcome, state)

      {:DOWN, ref, :process, _pid, reason} when is_map_key(running, ref) ->
        record(running, ref, {:failed, {:exit, reason}}, state)
    end
  end

  defp record(running, ref, outcome, state) do
    id = Map.fetch!(running, ref)

    state =
      case outcome do
        {:ok, value} -> %{state | completed: Map.put(state.completed, id, value)}
        {:failed, reason} -> %{state | failed: Map.put(state.failed, id, reason)}
      end

    {Map.delete(running, ref), state}
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
