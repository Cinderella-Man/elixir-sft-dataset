# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WeightedDAG do
  @moduledoc """
  A weighted Directed Acyclic Graph for task / project scheduling.

  Each vertex is a task with a non-negative numeric duration.  Edges express
  "must finish before" dependencies.  Beyond a plain topological sort, this
  module answers scheduling questions: earliest start/finish times, the total
  project makespan, and the critical path (the longest-duration dependent chain).

  Internally the struct holds:
    * `durations` – `%{id => duration}` (also serves as the vertex set).
    * `out_edges` – `%{id => MapSet of successors}` (forward adjacency).
    * `in_edges`  – `%{id => MapSet of predecessors}` (reverse adjacency).

  The graph is kept acyclic at all times; `add_dependency/3` eagerly rejects
  edges that would introduce a cycle (DFS-based detection).
  """

  @enforce_keys [:durations, :out_edges, :in_edges]
  defstruct [:durations, :out_edges, :in_edges]

  @type id :: term()
  @type t :: %__MODULE__{
          durations: %{id() => number()},
          out_edges: %{id() => MapSet.t()},
          in_edges: %{id() => MapSet.t()}
        }

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc """
  Returns a new, empty weighted DAG with no tasks and no dependencies.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{durations: %{}, out_edges: %{}, in_edges: %{}}
  end

  @doc """
  Adds a task vertex `id` with a non-negative numeric `duration`.

  If the task already exists the dag is returned unchanged, keeping the
  original duration.
  """
  @spec add_task(t(), id(), number()) :: t()
  def add_task(%__MODULE__{} = dag, id, duration)
      when is_number(duration) and duration >= 0 do
    if Map.has_key?(dag.durations, id) do
      dag
    else
      %{
        dag
        | durations: Map.put(dag.durations, id, duration),
          out_edges: Map.put_new(dag.out_edges, id, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, id, MapSet.new())
      }
    end
  end

  @doc """
  Adds a dependency edge meaning "`from` must finish before `to` starts".

  Both tasks must already exist.  Returns `{:ok, new_dag}` on success,
  `{:error, :task_not_found}` if either task is missing, or `{:error, :cycle}`
  if the edge would introduce a cycle (detected eagerly via DFS).
  """
  @spec add_dependency(t(), id(), id()) :: {:ok, t()} | {:error, :cycle | :task_not_found}
  def add_dependency(%__MODULE__{} = dag, from, to) do
    with :ok <- require_task(dag, from),
         :ok <- require_task(dag, to),
         :ok <- check_no_cycle(dag, from, to) do
      new_dag = %{
        dag
        | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_dag}
    end
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc """
  Returns the direct predecessors (incoming neighbours) of task `id`.
  """
  @spec predecessors(t(), id()) :: [id()]
  def predecessors(%__MODULE__{} = dag, id) do
    dag.in_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end

  @doc """
  Returns the direct successors (outgoing neighbours) of task `id`.
  """
  @spec successors(t(), id()) :: [id()]
  def successors(%__MODULE__{} = dag, id) do
    dag.out_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end

  @doc """
  Returns `{:ok, ordering}`, a topological order of the tasks (Kahn's
  algorithm).  Returns `{:ok, []}` for an empty graph.
  """
  @spec topological_sort(t()) :: {:ok, [id()]}
  def topological_sort(%__MODULE__{} = dag) do
    {:ok, topo_order(dag)}
  end

  @doc """
  Returns `{:ok, map}` where `map` is `%{id => earliest_start_time}`.

  A task's earliest start is the maximum over its direct predecessors of
  `(predecessor's earliest start + predecessor's duration)`, or `0` when it
  has no predecessors.
  """
  @spec earliest_start(t()) :: {:ok, %{id() => number()}}
  def earliest_start(%__MODULE__{} = dag) do
    {:ok, compute_est(dag)}
  end

  @doc """
  Returns `{:ok, map}` where each value is `earliest_start + duration`.
  """
  @spec earliest_finish(t()) :: {:ok, %{id() => number()}}
  def earliest_finish(%__MODULE__{} = dag) do
    est = compute_est(dag)
    eft = Map.new(est, fn {v, s} -> {v, s + Map.fetch!(dag.durations, v)} end)
    {:ok, eft}
  end

  @doc """
  Returns `{:ok, number}`, the total project duration: the maximum
  earliest-finish over all tasks.  Returns `{:ok, 0}` for an empty graph.
  """
  @spec makespan(t()) :: {:ok, number()}
  def makespan(%__MODULE__{} = dag) do
    span =
      dag
      |> compute_est()
      |> Enum.map(fn {v, s} -> s + Map.fetch!(dag.durations, v) end)
      |> case do
        [] -> 0
        finishes -> Enum.max(finishes)
      end

    {:ok, span}
  end

  @doc """
  Returns `{:ok, path}`, a list of task ids forming a longest-duration path
  from a source task to a sink task (the chain that determines the makespan).

  Ties are broken deterministically, preferring the smallest task id by term
  ordering.  Returns `{:ok, []}` for an empty graph.
  """
  @spec critical_path(t()) :: {:ok, [id()]}
  def critical_path(%__MODULE__{} = dag) do
    case topo_order(dag) do
      [] ->
        {:ok, []}

      _order ->
        est = compute_est(dag)
        eft = Map.new(est, fn {v, s} -> {v, s + Map.fetch!(dag.durations, v)} end)

        {end_v, _finish} =
          eft
          |> Enum.sort()
          |> Enum.max_by(fn {_v, f} -> f end)

        {:ok, backtrack(dag, est, end_v, [end_v])}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  # Earliest start time per task, computed over a topological order so that
  # every predecessor is resolved before the task itself.
  defp compute_est(dag) do
    Enum.reduce(topo_order(dag), %{}, fn v, est ->
      preds = Map.fetch!(dag.in_edges, v)

      start =
        if MapSet.size(preds) == 0 do
          0
        else
          preds
          |> Enum.map(fn p -> Map.fetch!(est, p) + Map.fetch!(dag.durations, p) end)
          |> Enum.max()
        end

      Map.put(est, v, start)
    end)
  end

  # Walk backwards from the makespan-determining sink, always following a
  # predecessor whose finish equals the current task's start (i.e. the tight
  # dependency). Ties broken by smallest id for determinism.
  defp backtrack(dag, est, current, acc) do
    start = Map.fetch!(est, current)

    candidates =
      dag.in_edges
      |> Map.fetch!(current)
      |> Enum.filter(fn p -> Map.fetch!(est, p) + Map.fetch!(dag.durations, p) == start end)
      |> Enum.sort()

    case candidates do
      [] -> acc
      [p | _] -> backtrack(dag, est, p, [p | acc])
    end
  end

  # Kahn's algorithm (BFS over in-degrees), sorted for determinism.
  defp topo_order(dag) do
    in_degree =
      Map.new(Map.keys(dag.durations), fn v ->
        {v, MapSet.size(Map.fetch!(dag.in_edges, v))}
      end)

    initial =
      in_degree
      |> Enum.filter(fn {_v, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    kahn(initial, in_degree, dag.out_edges, [])
  end

  defp kahn([], _in_degree, _out_edges, acc), do: Enum.reverse(acc)

  defp kahn([v | rest], in_degree, out_edges, acc) do
    {new_in_degree, newly_zero} =
      out_edges
      |> Map.fetch!(v)
      |> Enum.reduce({in_degree, []}, fn succ, {deg_map, zeros} ->
        new_deg = Map.fetch!(deg_map, succ) - 1
        updated = Map.put(deg_map, succ, new_deg)

        if new_deg == 0 do
          {updated, [succ | zeros]}
        else
          {updated, zeros}
        end
      end)

    kahn(rest ++ Enum.sort(newly_zero), new_in_degree, out_edges, [v | acc])
  end

  defp require_task(dag, id) do
    if Map.has_key?(dag.durations, id), do: :ok, else: {:error, :task_not_found}
  end

  defp check_no_cycle(_dag, from, from), do: {:error, :cycle}

  defp check_no_cycle(dag, from, to) do
    if dfs_reaches?(dag.out_edges, to, from), do: {:error, :cycle}, else: :ok
  end

  defp dfs_reaches?(out_edges, start, target) do
    do_dfs([start], MapSet.new(), out_edges, target)
  end

  defp do_dfs([], _visited, _out_edges, _target), do: false

  defp do_dfs([node | stack], visited, out_edges, target) do
    cond do
      node == target ->
        true

      MapSet.member?(visited, node) ->
        do_dfs(stack, visited, out_edges, target)

      true ->
        neighbors = out_edges |> Map.get(node, MapSet.new()) |> MapSet.to_list()
        do_dfs(neighbors ++ stack, MapSet.put(visited, node), out_edges, target)
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WeightedDAGTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  defp build(tasks, deps) do
    dag =
      Enum.reduce(tasks, WeightedDAG.new(), fn {id, dur}, acc ->
        WeightedDAG.add_task(acc, id, dur)
      end)

    Enum.reduce(deps, dag, fn {from, to}, acc ->
      {:ok, updated} = WeightedDAG.add_dependency(acc, from, to)
      updated
    end)
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "empty graph: sort, makespan, critical path" do
    dag = WeightedDAG.new()
    assert {:ok, []} = WeightedDAG.topological_sort(dag)
    assert {:ok, 0} = WeightedDAG.makespan(dag)
    assert {:ok, []} = WeightedDAG.critical_path(dag)
  end

  test "add_task/3 ignores duplicates and keeps original duration" do
    dag =
      WeightedDAG.new()
      |> WeightedDAG.add_task(:a, 5)
      |> WeightedDAG.add_task(:a, 99)

    {:ok, ef} = WeightedDAG.earliest_finish(dag)
    assert ef == %{a: 5}
  end

  # -------------------------------------------------------
  # Cycle detection
  # -------------------------------------------------------

  test "direct cycle is rejected eagerly" do
    dag = build([{:a, 1}, {:b, 1}], [{:a, :b}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :b, :a)
  end

  test "indirect cycle is rejected" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :b}, {:b, :c}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :c, :a)
  end

  # -------------------------------------------------------
  # Scheduling: linear chain
  # -------------------------------------------------------

  test "linear chain earliest start / finish / makespan / critical path" do
    dag = build([{:a, 3}, {:b, 2}, {:c, 4}], [{:a, :b}, {:b, :c}])

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 5}

    assert {:ok, eft} = WeightedDAG.earliest_finish(dag)
    assert eft == %{a: 3, b: 5, c: 9}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :b, :c]} = WeightedDAG.critical_path(dag)
  end

  # -------------------------------------------------------
  # Scheduling: diamond
  # -------------------------------------------------------

  test "diamond graph picks the heavier branch as critical path" do
    #        a(3)
    #       /    \
    #    b(2)    c(5)
    #       \    /
    #        d(1)
    dag =
      build(
        [{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}],
        [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
      )

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 3, d: 8}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :c, :d]} = WeightedDAG.critical_path(dag)
  end

  test "topological sort remains valid on the diamond" do
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    dag = build([{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}], edges)

    assert {:ok, order} = WeightedDAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end

  # -------------------------------------------------------
  # Isolated tasks
  # -------------------------------------------------------

  test "isolated task participates in makespan" do
    # TODO
  end

  # -------------------------------------------------------
  # Neighbours
  # -------------------------------------------------------

  test "predecessors and successors" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :c}, {:b, :c}])

    assert Enum.sort(WeightedDAG.predecessors(dag, :c)) == [:a, :b]
    assert WeightedDAG.successors(dag, :a) == [:c]
    assert WeightedDAG.successors(dag, :c) == []
  end
end
```
