defmodule MutableDAG do
  @moduledoc """
  A mutable Directed Acyclic Graph (DAG) implemented as a pure data structure.

  `MutableDAG` supports incremental construction and mutation (adding and
  removing vertices and edges), eager cycle detection with diagnostic cycle
  paths, topological sorting, and grouping of vertices into parallel-execution
  layers ("waves").

  There is no process or `GenServer` involved: every function takes a
  `MutableDAG` struct and returns either an updated struct or a result tuple.
  Vertices may be any term.

  The struct maintains three fields:

    * `:vertices` — a `MapSet` of all vertices,
    * `:outgoing` — a map from a vertex to a `MapSet` of its successors,
    * `:incoming` — a map from a vertex to a `MapSet` of its predecessors.

  Cycle detection is eager: `add_edge/3` performs a depth-first path search
  before inserting an edge and refuses any edge that would introduce a cycle.
  """

  @enforce_keys [:vertices, :outgoing, :incoming]
  defstruct vertices: MapSet.new(), outgoing: %{}, incoming: %{}

  @typedoc "A vertex, which may be any term."
  @type vertex :: term()

  @typedoc "The MutableDAG structure."
  @type t :: %__MODULE__{
          vertices: MapSet.t(vertex()),
          outgoing: %{optional(vertex()) => MapSet.t(vertex())},
          incoming: %{optional(vertex()) => MapSet.t(vertex())}
        }

  @doc """
  Returns a new, empty `MutableDAG`.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{vertices: MapSet.new(), outgoing: %{}, incoming: %{}}
  end

  @doc """
  Adds `vertex` to `dag`.

  If the vertex already exists, the DAG is returned unchanged.
  """
  @spec add_vertex(t(), vertex()) :: t()
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %__MODULE__{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          outgoing: Map.put(dag.outgoing, vertex, MapSet.new()),
          incoming: Map.put(dag.incoming, vertex, MapSet.new())
      }
    end
  end

  @doc """
  Adds a directed edge from `from` to `to`.

  Both vertices must already exist; otherwise `{:error, :vertex_not_found}` is
  returned. If the edge would introduce a cycle, `{:error, {:cycle, path}}` is
  returned, where `path` is the list of vertices forming the cycle, starting
  and ending with `from`. A self-loop yields `{:error, {:cycle, [from, from]}}`.

  If the edge already exists, `{:ok, dag}` is returned unchanged. On success,
  `{:ok, new_dag}` is returned.
  """
  @spec add_edge(t(), vertex(), vertex()) ::
          {:ok, t()} | {:error, :vertex_not_found} | {:error, {:cycle, [vertex()]}}
  def add_edge(%__MODULE__{} = dag, from, to) do
    cond do
      not MapSet.member?(dag.vertices, from) or not MapSet.member?(dag.vertices, to) ->
        {:error, :vertex_not_found}

      from == to ->
        {:error, {:cycle, [from, from]}}

      edge?(dag, from, to) ->
        {:ok, dag}

      true ->
        case find_path(dag, to, from) do
          {:ok, path} -> {:error, {:cycle, [from | path]}}
          :none -> {:ok, insert_edge(dag, from, to)}
        end
    end
  end

  @doc """
  Removes the directed edge from `from` to `to`, if present.

  If the edge or either vertex is absent, the DAG is returned unchanged.
  """
  @spec remove_edge(t(), vertex(), vertex()) :: t()
  def remove_edge(%__MODULE__{} = dag, from, to) do
    if edge?(dag, from, to) do
      %__MODULE__{
        dag
        | outgoing: Map.update!(dag.outgoing, from, &MapSet.delete(&1, to)),
          incoming: Map.update!(dag.incoming, to, &MapSet.delete(&1, from))
      }
    else
      dag
    end
  end

  @doc """
  Removes `vertex` and every edge incident to it (incoming and outgoing).

  If the vertex is absent, the DAG is returned unchanged.
  """
  @spec remove_vertex(t(), vertex()) :: t()
  def remove_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
      |> detach_successors(vertex)
      |> detach_predecessors(vertex)
      |> drop_vertex(vertex)
    else
      dag
    end
  end

  @doc """
  Returns `{:ok, ordering}`, a flat list of all vertices in a valid topological
  order. An empty graph yields `{:ok, []}`.
  """
  @spec topological_sort(t()) :: {:ok, [vertex()]}
  def topological_sort(%__MODULE__{} = dag) do
    indegrees =
      Map.new(dag.vertices, fn v -> {v, MapSet.size(incoming_set(dag, v))} end)

    available =
      indegrees
      |> Enum.filter(fn {_v, deg} -> deg == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    {:ok, do_topo_sort(dag, available, indegrees, [])}
  end

  @doc """
  Returns `{:ok, layers}`, a list of lists grouping vertices into parallel
  "waves".

  Layer 0 contains every vertex with no predecessors. Each subsequent layer
  contains the vertices whose predecessors have all appeared in earlier layers.
  Vertices within each layer are sorted by term ordering. An empty graph yields
  `{:ok, []}`.
  """
  @spec topological_layers(t()) :: {:ok, [[vertex()]]}
  def topological_layers(%__MODULE__{} = dag) do
    remaining = MapSet.to_list(dag.vertices)
    {:ok, do_layers(dag, remaining, MapSet.new(), [])}
  end

  @doc """
  Returns the direct predecessors (incoming neighbours) of `vertex`, sorted by
  term ordering. Returns `[]` when the vertex is absent.
  """
  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag |> incoming_set(vertex) |> MapSet.to_list() |> Enum.sort()
  end

  @doc """
  Returns the direct successors (outgoing neighbours) of `vertex`, sorted by
  term ordering. Returns `[]` when the vertex is absent.
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag |> outgoing_set(vertex) |> MapSet.to_list() |> Enum.sort()
  end

  # --- Internal helpers -------------------------------------------------------

  @spec edge?(t(), vertex(), vertex()) :: boolean()
  defp edge?(dag, from, to) do
    MapSet.member?(dag.vertices, from) and
      MapSet.member?(dag.vertices, to) and
      MapSet.member?(outgoing_set(dag, from), to)
  end

  @spec insert_edge(t(), vertex(), vertex()) :: t()
  defp insert_edge(dag, from, to) do
    %__MODULE__{
      dag
      | outgoing: Map.update!(dag.outgoing, from, &MapSet.put(&1, to)),
        incoming: Map.update!(dag.incoming, to, &MapSet.put(&1, from))
    }
  end

  @spec detach_successors(t(), vertex()) :: t()
  defp detach_successors(dag, vertex) do
    Enum.reduce(outgoing_set(dag, vertex), dag, fn succ, acc ->
      %__MODULE__{acc | incoming: Map.update!(acc.incoming, succ, &MapSet.delete(&1, vertex))}
    end)
  end

  @spec detach_predecessors(t(), vertex()) :: t()
  defp detach_predecessors(dag, vertex) do
    Enum.reduce(incoming_set(dag, vertex), dag, fn pred, acc ->
      %__MODULE__{acc | outgoing: Map.update!(acc.outgoing, pred, &MapSet.delete(&1, vertex))}
    end)
  end

  @spec drop_vertex(t(), vertex()) :: t()
  defp drop_vertex(dag, vertex) do
    %__MODULE__{
      dag
      | vertices: MapSet.delete(dag.vertices, vertex),
        outgoing: Map.delete(dag.outgoing, vertex),
        incoming: Map.delete(dag.incoming, vertex)
    }
  end

  @spec outgoing_set(t(), vertex()) :: MapSet.t(vertex())
  defp outgoing_set(dag, vertex), do: Map.get(dag.outgoing, vertex, MapSet.new())

  @spec incoming_set(t(), vertex()) :: MapSet.t(vertex())
  defp incoming_set(dag, vertex), do: Map.get(dag.incoming, vertex, MapSet.new())

  # Depth-first search for a path from `start` to `target` following outgoing
  # edges. Returns `{:ok, path}` (inclusive of both endpoints) or `:none`.
  @spec find_path(t(), vertex(), vertex()) :: {:ok, [vertex()]} | :none
  defp find_path(dag, start, target) do
    dfs(dag, start, target, MapSet.new())
  end

  @spec dfs(t(), vertex(), vertex(), MapSet.t(vertex())) :: {:ok, [vertex()]} | :none
  defp dfs(_dag, node, target, _visited) when node == target do
    {:ok, [node]}
  end

  defp dfs(dag, node, target, visited) do
    if MapSet.member?(visited, node) do
      :none
    else
      visited = MapSet.put(visited, node)

      dag
      |> outgoing_set(node)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce_while(:none, fn next, _acc ->
        case dfs(dag, next, target, visited) do
          {:ok, path} -> {:halt, {:ok, [node | path]}}
          :none -> {:cont, :none}
        end
      end)
    end
  end

  @spec do_topo_sort(t(), [vertex()], %{optional(vertex()) => non_neg_integer()}, [vertex()]) ::
          [vertex()]
  defp do_topo_sort(_dag, [], _indegrees, acc), do: Enum.reverse(acc)

  defp do_topo_sort(dag, [vertex | rest], indegrees, acc) do
    {available, indegrees} =
      dag
      |> outgoing_set(vertex)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce({rest, indegrees}, fn succ, {avail, degrees} ->
        new_degree = Map.fetch!(degrees, succ) - 1
        degrees = Map.put(degrees, succ, new_degree)
        avail = if new_degree == 0, do: insert_sorted(avail, succ), else: avail
        {avail, degrees}
      end)

    do_topo_sort(dag, available, indegrees, [vertex | acc])
  end

  @spec do_layers(t(), [vertex()], MapSet.t(vertex()), [[vertex()]]) :: [[vertex()]]
  defp do_layers(_dag, [], _placed, acc), do: Enum.reverse(acc)

  defp do_layers(dag, remaining, placed, acc) do
    layer =
      remaining
      |> Enum.filter(fn v ->
        dag |> incoming_set(v) |> Enum.all?(&MapSet.member?(placed, &1))
      end)
      |> Enum.sort()

    case layer do
      [] ->
        Enum.reverse(acc)

      _ ->
        placed = Enum.reduce(layer, placed, &MapSet.put(&2, &1))
        layer_set = MapSet.new(layer)
        remaining = Enum.reject(remaining, &MapSet.member?(layer_set, &1))
        do_layers(dag, remaining, placed, [layer | acc])
    end
  end

  @spec insert_sorted([vertex()], vertex()) :: [vertex()]
  defp insert_sorted([], value), do: [value]

  defp insert_sorted([head | tail] = list, value) do
    if value <= head do
      [value | list]
    else
      [head | insert_sorted(tail, value)]
    end
  end
end