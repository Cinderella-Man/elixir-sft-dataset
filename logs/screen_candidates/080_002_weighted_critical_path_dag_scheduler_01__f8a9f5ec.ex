defmodule WeightedDAG do
  @moduledoc """
  A weighted Directed Acyclic Graph (DAG) for project / task scheduling.

  Each vertex is a *task* identified by an arbitrary term and annotated with a
  non-negative numeric *duration*. Directed edges express dependencies: an edge
  `from -> to` means "`from` must finish before `to` starts".

  On top of a plain topological ordering, this structure answers the classic
  scheduling questions of the Critical Path Method (CPM):

    * `earliest_start/1` — the soonest each task may begin;
    * `earliest_finish/1` — earliest start plus duration;
    * `makespan/1` — the total project duration;
    * `critical_path/1` — the longest-duration chain of dependent tasks, i.e.
      the chain that determines the makespan.

  The structure is a pure value: every function takes a `t:t/0` and returns a
  new `t:t/0` (or a result tuple). There is no process or mutable state.

  Cycle detection is *eager*: `add_dependency/3` performs a depth-first search
  before inserting an edge and returns `{:error, :cycle}` rather than allowing
  the graph to become cyclic. Consequently every other operation can assume it
  is working with an acyclic graph.

  ## Example

      iex> dag = WeightedDAG.new()
      iex> dag = WeightedDAG.add_task(dag, :design, 3)
      iex> dag = WeightedDAG.add_task(dag, :build, 5)
      iex> dag = WeightedDAG.add_task(dag, :ship, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :design, :build)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :build, :ship)
      iex> WeightedDAG.makespan(dag)
      {:ok, 9}
      iex> WeightedDAG.critical_path(dag)
      {:ok, [:design, :build, :ship]}
  """

  @typedoc "A task identifier. May be any term."
  @type id :: term()

  @typedoc "A non-negative task duration."
  @type duration :: number()

  @typedoc """
  The graph.

  * `:durations` — `%{id => duration}`, also the authoritative vertex set;
  * `:out` — `%{id => MapSet.t(id)}` of direct successors;
  * `:in` — `%{id => MapSet.t(id)}` of direct predecessors.
  """
  @type t :: %__MODULE__{
          durations: %{id() => duration()},
          out: %{id() => MapSet.t(id())},
          in: %{id() => MapSet.t(id())}
        }

  defstruct durations: %{}, out: %{}, in: %{}

  @doc """
  Returns a new, empty graph.

  ## Examples

      iex> WeightedDAG.topological_sort(WeightedDAG.new())
      {:ok, []}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a task `id` with a non-negative numeric `duration`.

  If the task already exists the graph is returned unchanged, keeping the
  original duration. Raises `FunctionClauseError` if `duration` is not a
  non-negative number.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 4)
      iex> dag = WeightedDAG.add_task(dag, :a, 99)
      iex> WeightedDAG.earliest_finish(dag)
      {:ok, %{a: 4}}
  """
  @spec add_task(t(), id(), duration()) :: t()
  def add_task(%__MODULE__{} = dag, id, duration) when is_number(duration) and duration >= 0 do
    if Map.has_key?(dag.durations, id) do
      dag
    else
      %__MODULE__{
        dag
        | durations: Map.put(dag.durations, id, duration),
          out: Map.put(dag.out, id, MapSet.new()),
          in: Map.put(dag.in, id, MapSet.new())
      }
    end
  end

  @doc """
  Adds a dependency edge meaning "`from` must finish before `to` starts".

  Both tasks must already exist, otherwise `{:error, {:unknown_task, id}}` is
  returned. If the edge would introduce a cycle (including a self-loop) the
  graph is left untouched and `{:error, :cycle}` is returned. Adding an edge
  that already exists is a no-op returning `{:ok, dag}`.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 1) |> WeightedDAG.add_task(:b, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.add_dependency(dag, :b, :a)
      {:error, :cycle}
  """
  @spec add_dependency(t(), id(), id()) ::
          {:ok, t()} | {:error, :cycle} | {:error, {:unknown_task, id()}}
  def add_dependency(%__MODULE__{} = dag, from, to) do
    cond do
      not Map.has_key?(dag.durations, from) -> {:error, {:unknown_task, from}}
      not Map.has_key?(dag.durations, to) -> {:error, {:unknown_task, to}}
      from === to -> {:error, :cycle}
      reachable?(dag, to, from) -> {:error, :cycle}
      true -> {:ok, insert_edge(dag, from, to)}
    end
  end

  @doc """
  Returns `{:ok, ordering}`, a topological ordering of all tasks.

  Uses Kahn's algorithm: a breadth-first sweep over in-degrees. Ready tasks are
  emitted in ascending term order, which makes the ordering deterministic.
  Returns `{:ok, []}` for an empty graph.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:b, 1) |> WeightedDAG.add_task(:a, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :b, :a)
      iex> WeightedDAG.topological_sort(dag)
      {:ok, [:b, :a]}
  """
  @spec topological_sort(t()) :: {:ok, [id()]}
  def topological_sort(%__MODULE__{} = dag) do
    in_degrees =
      Map.new(dag.durations, fn {id, _duration} ->
        {id, MapSet.size(Map.fetch!(dag.in, id))}
      end)

    ready =
      in_degrees
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _degree} -> id end)
      |> Enum.sort()

    {:ok, kahn(dag, ready, in_degrees, [])}
  end

  @doc """
  Returns `{:ok, %{id => earliest_start_time}}` for every task.

  A task's earliest start is the maximum over its direct predecessors of
  `(predecessor's earliest start + predecessor's duration)`, or `0` when it has
  no predecessors.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 3) |> WeightedDAG.add_task(:b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.earliest_start(dag)
      {:ok, %{a: 0, b: 3}}
  """
  @spec earliest_start(t()) :: {:ok, %{id() => number()}}
  def earliest_start(%__MODULE__{} = dag) do
    {:ok, order} = topological_sort(dag)

    starts =
      Enum.reduce(order, %{}, fn id, acc ->
        start =
          dag.in
          |> Map.fetch!(id)
          |> Enum.reduce(0, fn pred, best ->
            max(best, Map.fetch!(acc, pred) + Map.fetch!(dag.durations, pred))
          end)

        Map.put(acc, id, start)
      end)

    {:ok, starts}
  end

  @doc """
  Returns `{:ok, %{id => earliest_finish_time}}`, i.e. earliest start plus duration.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 3) |> WeightedDAG.add_task(:b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.earliest_finish(dag)
      {:ok, %{a: 3, b: 5}}
  """
  @spec earliest_finish(t()) :: {:ok, %{id() => number()}}
  def earliest_finish(%__MODULE__{} = dag) do
    {:ok, starts} = earliest_start(dag)

    {:ok,
     Map.new(starts, fn {id, start} -> {id, start + Map.fetch!(dag.durations, id)} end)}
  end

  @doc """
  Returns `{:ok, makespan}`, the total project duration.

  The makespan is the maximum earliest-finish time over all tasks, or `0` for an
  empty graph.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 3) |> WeightedDAG.add_task(:b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.makespan(dag)
      {:ok, 5}
  """
  @spec makespan(t()) :: {:ok, number()}
  def makespan(%__MODULE__{} = dag) do
    {:ok, finishes} = earliest_finish(dag)

    if map_size(finishes) == 0 do
      {:ok, 0}
    else
      {:ok, finishes |> Map.values() |> Enum.max()}
    end
  end

  @doc """
  Returns `{:ok, path}`, a longest-duration path from a source task to a sink task.

  The returned chain is the one whose total duration equals the makespan — the
  critical path in CPM terms. Ties are broken deterministically by preferring
  the smallest task id under Erlang term ordering. Returns `{:ok, []}` for an
  empty graph.

  ## Examples

      iex> dag =
      ...>   WeightedDAG.new()
      ...>   |> WeightedDAG.add_task(:a, 1)
      ...>   |> WeightedDAG.add_task(:b, 5)
      ...>   |> WeightedDAG.add_task(:c, 1)
      ...>   |> WeightedDAG.add_task(:d, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :c)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :b, :d)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :c, :d)
      iex> WeightedDAG.critical_path(dag)
      {:ok, [:a, :b, :d]}
  """
  @spec critical_path(t()) :: {:ok, [id()]}
  def critical_path(%__MODULE__{} = dag) do
    {:ok, order} = topological_sort(dag)

    case order do
      [] ->
        {:ok, []}

      _ ->
        {finishes, parents} = longest_chains(dag, order)
        sink = best_sink(finishes)
        {:ok, walk_back(sink, parents, [])}
    end
  end

  @doc """
  Returns the direct predecessors of `id` as a list sorted ascending by term order.

  Returns `[]` for a task with no predecessors or for an unknown task.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 1) |> WeightedDAG.add_task(:b, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.predecessors(dag, :b)
      [:a]
  """
  @spec predecessors(t(), id()) :: [id()]
  def predecessors(%__MODULE__{} = dag, id), do: neighbours(dag.in, id)

  @doc """
  Returns the direct successors of `id` as a list sorted ascending by term order.

  Returns `[]` for a task with no successors or for an unknown task.

  ## Examples

      iex> dag = WeightedDAG.new() |> WeightedDAG.add_task(:a, 1) |> WeightedDAG.add_task(:b, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.successors(dag, :a)
      [:b]
  """
  @spec successors(t(), id()) :: [id()]
  def successors(%__MODULE__{} = dag, id), do: neighbours(dag.out, id)

  # -- internals -------------------------------------------------------------

  @spec neighbours(%{id() => MapSet.t(id())}, id()) :: [id()]
  defp neighbours(index, id) do
    case Map.fetch(index, id) do
      {:ok, set} -> set |> MapSet.to_list() |> Enum.sort()
      :error -> []
    end
  end

  @spec insert_edge(t(), id(), id()) :: t()
  defp insert_edge(dag, from, to) do
    %__MODULE__{
      dag
      | out: Map.update!(dag.out, from, &MapSet.put(&1, to)),
        in: Map.update!(dag.in, to, &MapSet.put(&1, from))
    }
  end

  # Eager DFS cycle check: is `target` reachable from `source` along existing edges?
  @spec reachable?(t(), id(), id()) :: boolean()
  defp reachable?(dag, source, target) do
    dfs(dag, [source], MapSet.new(), target)
  end

  @spec dfs(t(), [id()], MapSet.t(id()), id()) :: boolean()
  defp dfs(_dag, [], _seen, _target), do: false

  defp dfs(dag, [node | rest], seen, target) do
    cond do
      node === target ->
        true

      MapSet.member?(seen, node) ->
        dfs(dag, rest, seen, target)

      true ->
        next = dag.out |> Map.fetch!(node) |> MapSet.to_list()
        dfs(dag, next ++ rest, MapSet.put(seen, node), target)
    end
  end

  @spec kahn(t(), [id()], %{id() => non_neg_integer()}, [id()]) :: [id()]
  defp kahn(_dag, [], _in_degrees, acc), do: Enum.reverse(acc)

  defp kahn(dag, [id | rest], in_degrees, acc) do
    {ready, in_degrees} =
      dag
      |> successors(id)
      |> Enum.reduce({[], in_degrees}, fn succ, {ready, degrees} ->
        degrees = Map.update!(degrees, succ, &(&1 - 1))

        case Map.fetch!(degrees, succ) do
          0 -> {[succ | ready], degrees}
          _ -> {ready, degrees}
        end
      end)

    kahn(dag, merge_ready(rest, ready), in_degrees, [id | acc])
  end

  # Keeps the ready queue sorted so Kahn's output is deterministic.
  @spec merge_ready([id()], [id()]) :: [id()]
  defp merge_ready(queue, []), do: queue
  defp merge_ready(queue, ready), do: Enum.sort(queue ++ ready)

  # Longest-path DP over the topological order. Returns the best finish time per
  # task and the predecessor that achieves it (`nil` for sources).
  @spec longest_chains(t(), [id()]) :: {%{id() => number()}, %{id() => id() | nil}}
  defp longest_chains(dag, order) do
    Enum.reduce(order, {%{}, %{}}, fn id, {finishes, parents} ->
      candidates =
        dag
        |> predecessors(id)
        |> Enum.map(fn pred -> {Map.fetch!(finishes, pred), pred} end)

      {best_start, parent} = pick_best_start(candidates)
      duration = Map.fetch!(dag.durations, id)
      {Map.put(finishes, id, best_start + duration), Map.put(parents, id, parent)}
    end)
  end

  # Prefers the greatest predecessor finish; ties go to the smallest id.
  @spec pick_best_start([{number(), id()}]) :: {number(), id() | nil}
  defp pick_best_start([]), do: {0, nil}

  defp pick_best_start(candidates) do
    Enum.reduce(candidates, fn {finish, id} = candidate, {best_finish, best_id} = best ->
      cond do
        finish > best_finish -> candidate
        finish < best_finish -> best
        id < best_id -> candidate
        true -> best
      end
    end)
  end

  # The sink with the greatest finish time; ties go to the smallest id.
  @spec best_sink(%{id() => number()}) :: id()
  defp best_sink(finishes) do
    {_finish, sink} =
      finishes
      |> Enum.map(fn {id, finish} -> {finish, id} end)
      |> Enum.reduce(fn {finish, id} = candidate, {best_finish, best_id} = best ->
        cond do
          finish > best_finish -> candidate
          finish < best_finish -> best
          id < best_id -> candidate
          true -> best
        end
      end)

    sink
  end

  @spec walk_back(id() | nil, %{id() => id() | nil}, [id()]) :: [id()]
  defp walk_back(nil, _parents, acc), do: acc
  defp walk_back(id, parents, acc), do: walk_back(Map.fetch!(parents, id), parents, [id | acc])
end