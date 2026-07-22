defmodule WeightedDAG do
  @moduledoc """
  A weighted Directed Acyclic Graph (DAG) for project / task scheduling.

  Each vertex is a *task* identified by an arbitrary term and carries a
  non-negative numeric *duration*. Directed edges express dependencies:
  an edge `from -> to` means "`from` must finish before `to` starts".

  On top of a plain topological ordering, this module answers the classic
  scheduling questions of the Critical Path Method (CPM):

    * `earliest_start/1` — the soonest each task can begin;
    * `earliest_finish/1` — earliest start plus the task's own duration;
    * `makespan/1` — the total project duration;
    * `critical_path/1` — the longest-duration chain of dependent tasks,
      i.e. the chain that determines the makespan.

  The structure is pure data: every function takes a `t:t/0` and returns a
  new value. Cycle detection is eager — `add_dependency/3` refuses an edge
  that would close a cycle, so the graph is acyclic by construction and all
  scheduling queries are total.

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
  The graph itself.

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
  Adds task `id` with the given non-negative `duration`.

  If the task already exists the graph is returned unchanged, keeping the
  original duration. Raises `ArgumentError` when `duration` is not a
  non-negative number.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.new(), :a, 4)
      iex> dag = WeightedDAG.add_task(dag, :a, 99)
      iex> WeightedDAG.makespan(dag)
      {:ok, 4}
  """
  @spec add_task(t(), id(), duration()) :: t()
  def add_task(%__MODULE__{} = dag, id, duration) when is_number(duration) do
    unless duration >= 0 do
      raise ArgumentError, "duration must be non-negative, got: #{inspect(duration)}"
    end

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

  def add_task(%__MODULE__{}, _id, duration) do
    raise ArgumentError, "duration must be a non-negative number, got: #{inspect(duration)}"
  end

  @doc """
  Adds the dependency edge `from -> to` ("`from` must finish before `to` starts").

  Both tasks must already exist, otherwise `{:error, {:unknown_task, id}}` is
  returned. If the edge would close a cycle (including a self-loop),
  `{:error, :cycle}` is returned and the graph is left untouched. Duplicate
  edges are idempotent.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 1), :b, 2)
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
      from == to -> {:error, :cycle}
      reachable?(dag, to, from) -> {:error, :cycle}
      true -> {:ok, put_edge(dag, from, to)}
    end
  end

  @doc """
  Returns `{:ok, ordering}`, a topological ordering of all tasks.

  Uses Kahn's algorithm: a breadth-first sweep over in-degrees. Among tasks
  that become ready simultaneously the smallest id (by Erlang term ordering)
  is emitted first, so the ordering is deterministic. Since the graph is
  acyclic by construction this never fails; `{:ok, []}` for an empty graph.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 1), :b, 2)
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

  A task's earliest start is the maximum, over its direct predecessors, of
  `predecessor_earliest_start + predecessor_duration`; tasks with no
  predecessors start at `0`.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 3), :b, 2)
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

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 3), :b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.earliest_finish(dag)
      {:ok, %{a: 3, b: 5}}
  """
  @spec earliest_finish(t()) :: {:ok, %{id() => number()}}
  def earliest_finish(%__MODULE__{} = dag) do
    {:ok, starts} = earliest_start(dag)

    finishes =
      Map.new(starts, fn {id, start} -> {id, start + Map.fetch!(dag.durations, id)} end)

    {:ok, finishes}
  end

  @doc """
  Returns `{:ok, makespan}`, the total project duration.

  The makespan is the maximum earliest-finish time over all tasks, or `0` for
  an empty graph.

  ## Examples

      iex> WeightedDAG.makespan(WeightedDAG.new())
      {:ok, 0}
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

  The returned chain is the one whose total duration equals the makespan: any
  delay along it delays the whole project. Ties are broken deterministically by
  preferring the smallest task id (Erlang term ordering) at every choice point.
  `{:ok, []}` for an empty graph.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.new(), :a, 1)
      iex> dag = WeightedDAG.add_task(dag, :b, 5)
      iex> dag = WeightedDAG.add_task(dag, :c, 1)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :b, :c)
      iex> WeightedDAG.critical_path(dag)
      {:ok, [:a, :b, :c]}
  """
  @spec critical_path(t()) :: {:ok, [id()]}
  def critical_path(%__MODULE__{} = dag) do
    {:ok, order} = topological_sort(dag)

    case order do
      [] ->
        {:ok, []}

      _ ->
        {:ok, finishes} = earliest_finish(dag)
        best = longest_from(dag, order)
        {:ok, walk_critical_path(dag, best, finishes, order)}
    end
  end

  @doc """
  Returns the direct predecessors of `id` as a sorted list.

  Returns `{:error, {:unknown_task, id}}` when the task does not exist.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 1), :b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.predecessors(dag, :b)
      {:ok, [:a]}
  """
  @spec predecessors(t(), id()) :: {:ok, [id()]} | {:error, {:unknown_task, id()}}
  def predecessors(%__MODULE__{} = dag, id), do: neighbours(dag.in, dag, id)

  @doc """
  Returns the direct successors of `id` as a sorted list.

  Returns `{:error, {:unknown_task, id}}` when the task does not exist.

  ## Examples

      iex> dag = WeightedDAG.add_task(WeightedDAG.add_task(WeightedDAG.new(), :a, 1), :b, 2)
      iex> {:ok, dag} = WeightedDAG.add_dependency(dag, :a, :b)
      iex> WeightedDAG.successors(dag, :a)
      {:ok, [:b]}
  """
  @spec successors(t(), id()) :: {:ok, [id()]} | {:error, {:unknown_task, id()}}
  def successors(%__MODULE__{} = dag, id), do: neighbours(dag.out, dag, id)

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec neighbours(%{id() => MapSet.t(id())}, t(), id()) ::
          {:ok, [id()]} | {:error, {:unknown_task, id()}}
  defp neighbours(index, dag, id) do
    if Map.has_key?(dag.durations, id) do
      {:ok, index |> Map.fetch!(id) |> Enum.sort()}
    else
      {:error, {:unknown_task, id}}
    end
  end

  @spec put_edge(t(), id(), id()) :: t()
  defp put_edge(dag, from, to) do
    %__MODULE__{
      dag
      | out: Map.update!(dag.out, from, &MapSet.put(&1, to)),
        in: Map.update!(dag.in, to, &MapSet.put(&1, from))
    }
  end

  # Eager, DFS-based reachability: is `target` reachable from `source` by
  # following existing edges? Adding `from -> to` closes a cycle exactly when
  # `from` is already reachable from `to`.
  @spec reachable?(t(), id(), id()) :: boolean()
  defp reachable?(dag, source, target) do
    dfs(dag, [source], MapSet.new(), target)
  end

  @spec dfs(t(), [id()], MapSet.t(id()), id()) :: boolean()
  defp dfs(_dag, [], _seen, _target), do: false

  defp dfs(dag, [node | rest], seen, target) do
    cond do
      node == target ->
        true

      MapSet.member?(seen, node) ->
        dfs(dag, rest, seen, target)

      true ->
        next = dag.out |> Map.fetch!(node) |> MapSet.to_list()
        dfs(dag, next ++ rest, MapSet.put(seen, node), target)
    end
  end

  # Kahn's algorithm. `ready` is kept sorted so the ordering is deterministic.
  @spec kahn(t(), [id()], %{id() => non_neg_integer()}, [id()]) :: [id()]
  defp kahn(_dag, [], _in_degrees, acc), do: Enum.reverse(acc)

  defp kahn(dag, [id | rest], in_degrees, acc) do
    {ready, in_degrees} =
      dag.out
      |> Map.fetch!(id)
      |> Enum.sort()
      |> Enum.reduce({rest, in_degrees}, fn succ, {ready, degrees} ->
        degrees = Map.update!(degrees, succ, &(&1 - 1))

        if Map.fetch!(degrees, succ) == 0 do
          {insert_sorted(ready, succ), degrees}
        else
          {ready, degrees}
        end
      end)

    kahn(dag, ready, in_degrees, [id | acc])
  end

  @spec insert_sorted([id()], id()) :: [id()]
  defp insert_sorted([], id), do: [id]

  defp insert_sorted([head | tail] = list, id) do
    if id <= head, do: [id | list], else: [head | insert_sorted(tail, id)]
  end

  # For each task, the greatest total duration of any path starting at it
  # (inclusive of its own duration). Computed in reverse topological order.
  @spec longest_from(t(), [id()]) :: %{id() => number()}
  defp longest_from(dag, order) do
    order
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn id, acc ->
      tail =
        dag.out
        |> Map.fetch!(id)
        |> Enum.reduce(0, fn succ, best -> max(best, Map.fetch!(acc, succ)) end)

      Map.put(acc, id, Map.fetch!(dag.durations, id) + tail)
    end)
  end

  # Start at the source with the greatest downstream length, then always follow
  # the successor that preserves it. Ties break toward the smallest id.
  @spec walk_critical_path(t(), %{id() => number()}, %{id() => number()}, [id()]) :: [id()]
  defp walk_critical_path(dag, best, finishes, order) do
    total = finishes |> Map.values() |> Enum.max()

    start =
      order
      |> Enum.filter(fn id -> MapSet.size(Map.fetch!(dag.in, id)) == 0 end)
      |> Enum.filter(fn id -> Map.fetch!(best, id) == total end)
      |> Enum.sort()
      |> List.first()

    follow(dag, best, start, [])
  end

  @spec follow(t(), %{id() => number()}, id() | nil, [id()]) :: [id()]
  defp follow(_dag, _best, nil, acc), do: Enum.reverse(acc)

  defp follow(dag, best, id, acc) do
    remaining = Map.fetch!(best, id) - Map.fetch!(dag.durations, id)

    next =
      dag.out
      |> Map.fetch!(id)
      |> Enum.filter(fn succ -> Map.fetch!(best, succ) == remaining end)
      |> Enum.sort()
      |> List.first()

    follow(dag, best, next, [id | acc])
  end
end