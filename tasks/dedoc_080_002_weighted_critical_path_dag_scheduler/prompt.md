# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule WeightedDAG do
  @enforce_keys [:durations, :out_edges, :in_edges]
  defstruct [:durations, :out_edges, :in_edges]

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  def new do
    %__MODULE__{durations: %{}, out_edges: %{}, in_edges: %{}}
  end

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

  def predecessors(%__MODULE__{} = dag, id) do
    dag.in_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end

  def successors(%__MODULE__{} = dag, id) do
    dag.out_edges |> Map.get(id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end

  def topological_sort(%__MODULE__{} = dag) do
    {:ok, topo_order(dag)}
  end

  def earliest_start(%__MODULE__{} = dag) do
    {:ok, compute_est(dag)}
  end

  def earliest_finish(%__MODULE__{} = dag) do
    est = compute_est(dag)
    eft = Map.new(est, fn {v, s} -> {v, s + Map.fetch!(dag.durations, v)} end)
    {:ok, eft}
  end

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
