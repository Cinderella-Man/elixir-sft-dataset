defmodule TaskRunner do
  @moduledoc """
  A `GenServer` that collects tasks with declared dependencies and executes them
  in a valid topological order, running independent tasks concurrently.

  Tasks are registered with `submit/3` and nothing executes until `run_all/1` is
  called. `run_all/1` first validates the dependency graph: if a task references
  an unknown dependency, or the graph contains a cycle, no task is executed and
  an error tuple is returned.

  Execution proceeds layer by layer. Every task whose dependencies have already
  finished is started in its own process, so a wide layer of independent tasks
  takes roughly as long as the slowest single task in that layer rather than the
  sum of them.

      {:ok, _pid} = TaskRunner.start_link(name: :runner)
      :ok = TaskRunner.submit(:runner, :a, func: fn -> 1 end)
      :ok = TaskRunner.submit(:runner, :b, depends_on: [:a], func: fn -> 2 end)
      {:ok, %{a: 1, b: 2}} = TaskRunner.run_all(:runner)
  """

  use GenServer

  @typedoc "Any term uniquely identifying a task."
  @type task_id :: term()

  @typedoc "Options accepted by `submit/3`."
  @type submit_opts :: [depends_on: [task_id()], func: (-> term())]

  @typedoc "Reasons `run_all/1` can refuse to execute the graph."
  @type run_error :: {:cycle, [task_id()]} | {:unknown_dependencies, [task_id()]}

  defmodule Task do
    @moduledoc false
    defstruct [:id, :func, deps: []]
  end

  ## Public API

  @doc """
  Starts the runner process.

  Options are forwarded to `GenServer.start_link/3`; `:name` is used for process
  registration so the runner can be addressed by an atom in the other functions.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Registers `task_id` with the runner.

  Options:

    * `:func` — required zero-arity function to execute.
    * `:depends_on` — optional list of task ids that must finish first
      (defaults to `[]`).

  Re-submitting an existing `task_id` overwrites the previous definition. The
  function is not executed here; it only runs during `run_all/1`.
  """
  @spec submit(GenServer.server(), task_id(), submit_opts()) :: :ok
  def submit(name, task_id, opts) do
    func = Keyword.fetch!(opts, :func)

    unless is_function(func, 0) do
      raise ArgumentError, ":func must be a zero-arity function, got: #{inspect(func)}"
    end

    deps = opts |> Keyword.get(:depends_on, []) |> List.wrap()
    GenServer.call(name, {:submit, %Task{id: task_id, func: func, deps: deps}})
  end

  @doc """
  Validates the dependency graph and then executes every submitted task.

  Returns `{:ok, results}` — a map of `task_id => value returned by :func` — on
  success. Returns `{:error, {:unknown_dependencies, missing}}` or
  `{:error, {:cycle, involved}}` without running anything when the graph is
  invalid. A runner with no tasks returns `{:ok, %{}}`.
  """
  @spec run_all(GenServer.server(), timeout()) :: {:ok, %{task_id() => term()}} | {:error, run_error()}
  def run_all(name, timeout \\ :infinity) do
    GenServer.call(name, :run_all, timeout)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(:ok), do: {:ok, %{tasks: %{}, order: []}}

  @impl GenServer
  def handle_call({:submit, %Task{id: id} = task}, _from, state) do
    order = if Map.has_key?(state.tasks, id), do: state.order, else: state.order ++ [id]
    {:reply, :ok, %{state | tasks: Map.put(state.tasks, id, task), order: order}}
  end

  def handle_call(:run_all, _from, state) do
    {:reply, execute(state), state}
  end

  ## Internal helpers

  @spec execute(map()) :: {:ok, %{task_id() => term()}} | {:error, run_error()}
  defp execute(%{tasks: tasks}) when map_size(tasks) == 0, do: {:ok, %{}}

  defp execute(%{tasks: tasks, order: order}) do
    with :ok <- check_unknown_deps(tasks, order),
         {:ok, layers} <- topological_layers(tasks, order) do
      {:ok, run_layers(layers, tasks)}
    end
  end

  @spec check_unknown_deps(%{task_id() => Task.t()}, [task_id()]) ::
          :ok | {:error, {:unknown_dependencies, [task_id()]}}
  defp check_unknown_deps(tasks, order) do
    missing =
      order
      |> Enum.flat_map(fn id -> Map.fetch!(tasks, id).deps end)
      |> Enum.reject(&Map.has_key?(tasks, &1))
      |> Enum.uniq()

    if missing == [], do: :ok, else: {:error, {:unknown_dependencies, missing}}
  end

  # Kahn's algorithm, collecting ready tasks one whole layer at a time so each
  # layer can be executed concurrently.
  @spec topological_layers(%{task_id() => Task.t()}, [task_id()]) ::
          {:ok, [[task_id()]]} | {:error, {:cycle, [task_id()]}}
  defp topological_layers(tasks, order) do
    deps = Map.new(order, fn id -> {id, tasks |> Map.fetch!(id) |> uniq_deps()} end)
    build_layers(deps, order, [])
  end

  @spec uniq_deps(Task.t()) :: MapSet.t()
  defp uniq_deps(%Task{id: id, deps: deps}) do
    deps |> MapSet.new() |> MapSet.delete(id) |> then(&maybe_self_loop(&1, id, deps))
  end

  # A self-dependency is a cycle of length one; keep it so it is detected.
  @spec maybe_self_loop(MapSet.t(), task_id(), [task_id()]) :: MapSet.t()
  defp maybe_self_loop(set, id, deps) do
    if id in deps, do: MapSet.put(set, id), else: set
  end

  @spec build_layers(%{task_id() => MapSet.t()}, [task_id()], [[task_id()]]) ::
          {:ok, [[task_id()]]} | {:error, {:cycle, [task_id()]}}
  defp build_layers(deps, _order, acc) when map_size(deps) == 0 do
    {:ok, Enum.reverse(acc)}
  end

  defp build_layers(deps, order, acc) do
    ready = Enum.filter(order, fn id -> Map.has_key?(deps, id) and MapSet.size(deps[id]) == 0 end)

    case ready do
      [] ->
        {:error, {:cycle, find_cycle(deps, order)}}

      _ ->
        done = MapSet.new(ready)

        remaining =
          deps
          |> Map.drop(ready)
          |> Map.new(fn {id, set} -> {id, MapSet.difference(set, done)} end)

        build_layers(remaining, order -- ready, [ready | acc])
    end
  end

  # Every node left in `deps` is on, or feeds into, a cycle. Walk forward from
  # the first remaining node until a node repeats; the repeated segment is the
  # actual cycle.
  @spec find_cycle(%{task_id() => MapSet.t()}, [task_id()]) :: [task_id()]
  defp find_cycle(deps, order) do
    start = Enum.find(order, &Map.has_key?(deps, &1))
    walk_cycle(deps, start, [])
  end

  @spec walk_cycle(%{task_id() => MapSet.t()}, task_id(), [task_id()]) :: [task_id()]
  defp walk_cycle(deps, current, path) do
    if current in path do
      path |> Enum.reverse() |> Enum.drop_while(&(&1 != current))
    else
      next = deps |> Map.fetch!(current) |> Enum.find(&Map.has_key?(deps, &1))
      walk_cycle(deps, next, [current | path])
    end
  end

  @spec run_layers([[task_id()]], %{task_id() => Task.t()}) :: %{task_id() => term()}
  defp run_layers(layers, tasks) do
    Enum.reduce(layers, %{}, fn layer, results ->
      layer
      |> Enum.map(fn id -> {id, spawn_task(tasks[id])} end)
      |> Enum.reduce(results, fn {id, task}, acc ->
        Map.put(acc, id, Elixir.Task.await(task, :infinity))
      end)
    end)
  end

  @spec spawn_task(Task.t()) :: Elixir.Task.t()
  defp spawn_task(%Task{func: func}) do
    Elixir.Task.async(func)
  end
end