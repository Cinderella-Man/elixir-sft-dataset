defmodule TaskRunner do
  @moduledoc """
  A `GenServer` that accepts tasks with dependencies and executes them in a
  valid topological order, running independent tasks concurrently.

  Tasks are registered with `submit/3` and only executed once `run_all/1` is
  called. Execution is dependency-driven rather than layered: every task is
  started the moment its own dependencies have finished, regardless of any
  unrelated work that may still be running. As a result a wide set of
  independent tasks takes roughly as long as the single slowest one.
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
  @spec submit(GenServer.server(), term(), keyword()) :: :ok
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
  graph contains a cycle, where `involved` lists only the tasks that actually
  take part in a cycle. In both error cases no task is executed.
  """
  @spec run_all(GenServer.server()) ::
          {:ok, %{optional(term()) => term()}}
          | {:error, {:cycle, [term()]}}
          | {:error, {:unknown_dependencies, [term()]}}
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
           :ok <- check_cycles(tasks) do
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

  defp check_cycles(tasks) do
    remaining = kahn(build_in_degree(tasks), build_dependents(tasks))

    if remaining == [] do
      :ok
    else
      {:error, {:cycle, cycle_members(MapSet.new(remaining), tasks)}}
    end
  end

  # Repeatedly removes tasks whose dependencies are all satisfied. Whatever is
  # left over is a cycle, or hangs off one.
  defp kahn(in_degree, dependents) do
    ready = for {id, 0} <- in_degree, do: id

    case ready do
      [] -> Map.keys(in_degree)
      _ -> kahn(release(Map.drop(in_degree, ready), ready, dependents), dependents)
    end
  end

  # Narrows the leftover set down to the tasks that really sit on a cycle by
  # repeatedly dropping tasks that nothing else in the set depends on.
  defp cycle_members(set, tasks) do
    kept =
      set
      |> Enum.filter(fn id ->
        Enum.any?(set, fn other -> id in deps_of(tasks, other) end)
      end)
      |> MapSet.new()

    if MapSet.size(kept) == MapSet.size(set) do
      MapSet.to_list(set)
    else
      cycle_members(kept, tasks)
    end
  end

  # ── Graph helpers ───────────────────────────────────────────────────────

  defp build_in_degree(tasks) do
    Map.new(tasks, fn {id, %{depends_on: deps}} -> {id, length(Enum.uniq(deps))} end)
  end

  defp build_dependents(tasks) do
    Enum.reduce(tasks, %{}, fn {id, %{depends_on: deps}}, acc ->
      deps
      |> Enum.uniq()
      |> Enum.reduce(acc, fn dep, acc2 -> Map.update(acc2, dep, [id], &[id | &1]) end)
    end)
  end

  defp deps_of(tasks, id) do
    %{depends_on: deps} = Map.fetch!(tasks, id)
    deps
  end

  # Decrements the pending dependency count of everything depending on `done`.
  defp release(pending, done, dependents) do
    Enum.reduce(done, pending, fn id, acc ->
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

  # ── Execution ───────────────────────────────────────────────────────────

  defp execute(tasks) do
    dependents = build_dependents(tasks)
    {pending, running} = start_ready(build_in_degree(tasks), tasks, %{})
    collect(pending, running, dependents, tasks, %{})
  end

  # Starts every task whose dependency count has reached zero and returns the
  # still-blocked tasks together with the updated ref => task_id map.
  defp start_ready(pending, tasks, running) do
    ready = for {id, 0} <- pending, do: id

    running =
      Enum.reduce(ready, running, fn id, acc ->
        %{func: func} = Map.fetch!(tasks, id)
        %Task{ref: ref} = Task.async(func)
        Map.put(acc, ref, id)
      end)

    {Map.drop(pending, ready), running}
  end

  defp collect(_pending, running, _dependents, _tasks, results) when map_size(running) == 0 do
    results
  end

  defp collect(pending, running, dependents, tasks, results) do
    {ref, value} = await_one(running)
    id = Map.fetch!(running, ref)
    Process.demonitor(ref, [:flush])

    running = Map.delete(running, ref)
    results = Map.put(results, id, value)
    {pending, running} = start_ready(release(pending, [id], dependents), tasks, running)

    collect(pending, running, dependents, tasks, results)
  end

  # Selectively waits for the next task reply, ignoring unrelated messages in
  # the mailbox.
  defp await_one(running) do
    receive do
      {ref, value} when is_map_key(running, ref) -> {ref, value}
    end
  end
end
