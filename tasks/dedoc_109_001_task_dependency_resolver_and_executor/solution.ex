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
