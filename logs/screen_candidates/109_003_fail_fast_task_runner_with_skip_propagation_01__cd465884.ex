defmodule ResilientRunner do
  @moduledoc """
  A `GenServer` that runs a graph of inter-dependent tasks with fail-fast
  containment.

  Tasks are registered with `submit/3` and executed with `run_all/1`. Execution
  respects dependency order: a task's function is only invoked once every one of
  its dependencies has finished executing. Tasks that are ready at the same time
  and do not depend on one another run concurrently.

  Failure containment is precise: when a task fails (returns `{:error, reason}`
  or raises/throws) every task that transitively depends on it is skipped, and
  nothing else is affected. Unrelated branches of the graph still run to
  completion, and the runner process itself never crashes because of a failing
  task.

  Before executing anything the graph is validated: dependency cycles and
  references to tasks that were never submitted abort the run without invoking a
  single function.
  """

  use GenServer

  @typedoc "Identifier of a submitted task. Any term is accepted."
  @type task_id :: term()

  @typedoc "Outcome summary returned by `run_all/1`."
  @type report :: %{
          completed: %{optional(task_id()) => term()},
          failed: %{optional(task_id()) => term()},
          skipped: [task_id()]
        }

  defmodule Task do
    @moduledoc false
    defstruct [:id, :func, depends_on: []]
  end

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the runner.

  Options are forwarded to `GenServer.start_link/3`; the `:name` option is used
  for process registration.

      iex> {:ok, pid} = ResilientRunner.start_link(name: :my_runner)
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Registers a task under `task_id`.

  Options:

    * `:func` — required zero-arity function to execute.
    * `:depends_on` — list of task ids this task depends on, defaults to `[]`.

  Submitting an existing `task_id` overwrites the previous definition. Nothing
  is executed until `run_all/1` is called.
  """
  @spec submit(GenServer.server(), task_id(), keyword()) :: :ok
  def submit(name, task_id, opts) do
    func = Keyword.fetch!(opts, :func)

    unless is_function(func, 0) do
      raise ArgumentError, ":func must be a zero-arity function, got: #{inspect(func)}"
    end

    depends_on = opts |> Keyword.get(:depends_on, []) |> List.wrap()
    task = %Task{id: task_id, func: func, depends_on: Enum.uniq(depends_on)}
    GenServer.call(name, {:submit, task})
  end

  @doc """
  Validates the dependency graph and executes every submitted task.

  Returns `{:ok, %{completed: map, failed: map, skipped: list}}` on a successful
  run — individual task failures are reported in `failed`, not raised.

  Returns `{:error, {:cycle, involved}}` or
  `{:error, {:unknown_dependencies, missing}}` without running any task when the
  graph is invalid.
  """
  @spec run_all(GenServer.server()) ::
          {:ok, report()}
          | {:error, {:cycle, [task_id()]}}
          | {:error, {:unknown_dependencies, [task_id()]}}
  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(:ok), do: {:ok, %{tasks: %{}}}

  @impl true
  def handle_call({:submit, %Task{id: id} = task}, _from, state) do
    {:reply, :ok, put_in(state.tasks[id], task)}
  end

  def handle_call(:run_all, _from, %{tasks: tasks} = state) do
    {:reply, execute(tasks), state}
  end

  # ── Execution ───────────────────────────────────────────────────────────────

  @spec execute(%{optional(task_id()) => %Task{}}) ::
          {:ok, report()} | {:error, {:cycle, [task_id()]} | {:unknown_dependencies, [task_id()]}}
  defp execute(tasks) when map_size(tasks) == 0 do
    {:ok, %{completed: %{}, failed: %{}, skipped: []}}
  end

  defp execute(tasks) do
    with :ok <- validate_dependencies(tasks),
         :ok <- validate_acyclic(tasks) do
      {:ok, run_graph(tasks)}
    end
  end

  @spec validate_dependencies(%{optional(task_id()) => %Task{}}) ::
          :ok | {:error, {:unknown_dependencies, [task_id()]}}
  defp validate_dependencies(tasks) do
    missing =
      tasks
      |> Map.values()
      |> Enum.flat_map(& &1.depends_on)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(tasks, &1))

    if missing == [], do: :ok, else: {:error, {:unknown_dependencies, missing}}
  end

  @spec validate_acyclic(%{optional(task_id()) => %Task{}}) :: :ok | {:error, {:cycle, [task_id()]}}
  defp validate_acyclic(tasks) do
    remaining = peel(Map.new(tasks, fn {id, t} -> {id, MapSet.new(t.depends_on)} end))

    if map_size(remaining) == 0 do
      :ok
    else
      {:error, {:cycle, remaining |> Map.keys() |> Enum.sort_by(&inspect/1)}}
    end
  end

  # Repeatedly removes tasks with no unresolved dependencies. Whatever is left
  # over is exactly the set of tasks involved in (or fed only by) a cycle.
  @spec peel(%{optional(task_id()) => MapSet.t()}) :: %{optional(task_id()) => MapSet.t()}
  defp peel(pending) do
    ready = for {id, deps} <- pending, MapSet.size(deps) == 0, do: id

    case ready do
      [] ->
        pending

      ready ->
        ready_set = MapSet.new(ready)

        pending
        |> Map.drop(ready)
        |> Map.new(fn {id, deps} -> {id, MapSet.difference(deps, ready_set)} end)
        |> peel()
    end
  end

  @spec run_graph(%{optional(task_id()) => %Task{}}) :: report()
  defp run_graph(tasks) do
    state = %{
      tasks: tasks,
      pending: Map.new(tasks, fn {id, t} -> {id, MapSet.new(t.depends_on)} end),
      dependents: build_dependents(tasks),
      running: %{},
      completed: %{},
      failed: %{},
      skipped: []
    }

    state = loop(state)
    %{completed: state.completed, failed: state.failed, skipped: Enum.reverse(state.skipped)}
  end

  @spec build_dependents(%{optional(task_id()) => %Task{}}) :: %{optional(task_id()) => [task_id()]}
  defp build_dependents(tasks) do
    base = Map.new(tasks, fn {id, _} -> {id, []} end)

    Enum.reduce(tasks, base, fn {id, task}, acc ->
      Enum.reduce(task.depends_on, acc, fn dep, inner ->
        Map.update(inner, dep, [id], &[id | &1])
      end)
    end)
  end

  # Spawns every currently-ready task, waits for the first one to report back,
  # applies its outcome, and repeats until nothing is pending or running.
  @spec loop(map()) :: map()
  defp loop(state) do
    state = start_ready(state)

    cond do
      map_size(state.running) > 0 -> state |> await_one() |> loop()
      map_size(state.pending) > 0 -> state |> loop()
      true -> state
    end
  end

  @spec start_ready(map()) :: map()
  defp start_ready(state) do
    ready = for {id, deps} <- state.pending, MapSet.size(deps) == 0, do: id

    Enum.reduce(ready, state, fn id, acc ->
      task = Map.fetch!(acc.tasks, id)
      {pid, ref} = spawn_task(id, task.func)

      acc
      |> Map.update!(:pending, &Map.delete(&1, id))
      |> Map.update!(:running, &Map.put(&1, ref, {id, pid}))
    end)
  end

  @spec spawn_task(task_id(), (-> term())) :: {pid(), reference()}
  defp spawn_task(id, func) do
    parent = self()

    spawn_monitor(fn ->
      send(parent, {:task_done, self(), id, safe_apply(func)})
    end)
  end

  @spec safe_apply((-> term())) :: {:ok, term()} | {:error, term()}
  defp safe_apply(func) do
    try do
      case func.() do
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    rescue
      exception -> {:error, exception}
    catch
      :throw, value -> {:error, {:throw, value}}
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  # Blocks until exactly one running task reports an outcome (or dies without
  # reporting), then folds that outcome into the state.
  @spec await_one(map()) :: map()
  defp await_one(state) do
    receive do
      {:task_done, _pid, id, outcome} ->
        state |> settle(id, outcome) |> drain_down(id)

      {:DOWN, ref, :process, _pid, reason} ->
        case Map.fetch(state.running, ref) do
          {:ok, {id, _pid}} -> settle(state, id, {:error, {:exit, reason}})
          :error -> state
        end
    end
  end

  # A reported task is still monitored; consume its :DOWN so it cannot be
  # mistaken for an unreported crash later on.
  @spec drain_down(map(), task_id()) :: map()
  defp drain_down(state, id) do
    receive do
      {:DOWN, _ref, :process, _pid, _reason} -> state
    after
      5_000 -> state
    end
    |> tap(fn _ -> id end)
  end

  @spec settle(map(), task_id(), {:ok, term()} | {:error, term()}) :: map()
  defp settle(state, id, outcome) do
    state =
      Map.update!(state, :running, fn running ->
        running
        |> Enum.reject(fn {_ref, {running_id, _pid}} -> running_id == id end)
        |> Map.new()
      end)

    case outcome do
      {:ok, value} ->
        state
        |> Map.update!(:completed, &Map.put(&1, id, value))
        |> release_dependents(id)

      {:error, reason} ->
        state
        |> Map.update!(:failed, &Map.put(&1, id, reason))
        |> prune(id)
    end
  end

  # Marks `id` as satisfied for each of its dependents, making them ready once
  # their last dependency clears.
  @spec release_dependents(map(), task_id()) :: map()
  defp release_dependents(state, id) do
    Enum.reduce(dependents_of(state, id), state, fn dep_id, acc ->
      Map.update!(acc, :pending, fn pending ->
        case Map.fetch(pending, dep_id) do
          {:ok, deps} -> Map.put(pending, dep_id, MapSet.delete(deps, id))
          :error -> pending
        end
      end)
    end)
  end

  # Skips exactly the subgraph reachable from a failed or skipped task.
  @spec prune(map(), task_id()) :: map()
  defp prune(state, id) do
    Enum.reduce(dependents_of(state, id), state, fn dep_id, acc ->
      if Map.has_key?(acc.pending, dep_id) do
        acc
        |> Map.update!(:pending, &Map.delete(&1, dep_id))
        |> Map.update!(:skipped, &[dep_id | &1])
        |> prune(dep_id)
      else
        acc
      end
    end)
  end

  @spec dependents_of(map(), task_id()) :: [task_id()]
  defp dependents_of(state, id), do: Map.get(state.dependents, id, [])
end