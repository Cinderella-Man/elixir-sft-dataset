defmodule MutableDAG do
  @moduledoc """
  A mutable Directed Acyclic Graph (DAG) implemented as a pure data structure.

  `MutableDAG` supports adding and removing both vertices and edges, eager
  cycle detection with diagnostic cycle paths, topological sorting, and
  grouping of vertices into "parallel-execution layers".

  Every function takes a `MutableDAG` struct and returns either an updated
  struct or a result tuple. No processes or mutable state are involved; the
  structure is entirely value based.

  Internally the graph keeps:

    * `:vertices` — a `MapSet` of every vertex,
    * `:out`      — a map of vertex => `MapSet` of direct successors,
    * `:in`       — a map of vertex => `MapSet` of direct predecessors.

  Vertices may be any Elixir term.
  """

  @typedoc "Any term may be used as a vertex."
  @type vertex :: term()

  @typedoc "The DAG structure."
  @type t :: %__MODULE__{
          vertices: MapSet.t(vertex),
          out: %{optional(vertex) => MapSet.t(vertex)},
          in: %{optional(vertex) => MapSet.t(vertex)}
        }

  defstruct vertices: MapSet.new(), out: %{}, in: %{}

  @doc """
  Returns a new, empty `MutableDAG`.
  """
  @spec new() :: t
  def new, do: %__MODULE__{}

  @doc """
  Adds `vertex` to the graph.

  If the vertex already exists the graph is returned unchanged.
  """
  @spec add_vertex(t, vertex) :: t
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %__MODULE__{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          out: Map.put(dag.out, vertex, MapSet.new()),
          in: Map.put(dag.in, vertex, MapSet.new())
      }
    end
  end

  @doc """
  Adds a directed edge from `from` to `to`.

  Both endpoints must already exist; otherwise `{:error, :vertex_not_found}`
  is returned. If adding the edge would introduce a cycle, returns
  `{:error, {:cycle, path}}` where `path` is the offending cycle, starting and
  ending with `from`. On success returns `{:ok, new_dag}`.
  """
  @spec add_edge(t, vertex, vertex) ::
          {:ok, t} | {:error, :vertex_not_found} | {:error, {:cycle, [vertex]}}
  def add_edge(%__MODULE__{} = dag, from, to) do
    cond do
      not (MapSet.member?(dag.vertices, from) and MapSet.member?(dag.vertices, to)) ->
        {:error, :vertex_not_found}

      path = find_path(dag, to, from) ->
        {:error, {:cycle, [from | path]}}

      true ->
        {:ok, insert_edge(dag, from, to)}
    end
  end

  @doc """
  Removes the directed edge from `from` to `to`.

  If either vertex or the edge itself is absent, the graph is returned
  unchanged.
  """
  @spec remove_edge(t, vertex, vertex) :: t
  def remove_edge(%__MODULE__{} = dag, from, to) do
    with true <- MapSet.member?(dag.vertices, from),
         true <- MapSet.member?(dag.vertices, to),
         true <- MapSet.member?(successors_set(dag, from), to) do
      %__MODULE__{
        dag
        | out: Map.update!(dag.out, from, &MapSet.delete(&1, to)),
          in: Map.update!(dag.in, to, &MapSet.delete(&1, from))
      }
    else
      _ -> dag
    end
  end

  @doc """
  Removes `vertex` and every edge incident to it (incoming and outgoing).

  If the vertex is absent the graph is returned unchanged.
  """
  @spec remove_vertex(t, vertex) :: t
  def remove_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      succ = successors_set(dag, vertex)
      pred = predecessors_set(dag, vertex)

      in_map =
        Enum.reduce(succ, dag.in, fn s, acc ->
          Map.update!(acc, s, &MapSet.delete(&1, vertex))
        end)

      out_map =
        Enum.reduce(pred, dag.out, fn p, acc ->
          Map.update!(acc, p, &MapSet.delete(&1, vertex))
        end)

      %__MODULE__{
        vertices: MapSet.delete(dag.vertices, vertex),
        out: Map.delete(out_map, vertex),
        in: Map.delete(in_map, vertex)
      }
    else
      dag
    end
  end

  @doc """
  Returns `{:ok, ordering}` with all vertices in a valid topological order.

  Returns `{:ok, []}` for an empty graph.
  """
  @spec topological_sort(t) :: {:ok, [vertex]}
  def topological_sort(%__MODULE__{} = dag) do
    {:ok, layers} = topological_layers(dag)
    {:ok, Enum.concat(layers)}
  end

  @doc """
  Groups vertices into parallel-execution layers.

  Layer 0 holds every vertex with no predecessors; each later layer holds the
  vertices whose predecessors have all appeared in earlier layers. Vertices
  within a layer are sorted by Elixir term ordering for determinism.

  Returns `{:ok, []}` for an empty graph.
  """
  @spec topological_layers(t) :: {:ok, [[vertex]]}
  def topological_layers(%__MODULE__{} = dag) do
    indeg =
      for v <- dag.vertices, into: %{} do
        {v, MapSet.size(Map.fetch!(dag.in, v))}
      end

    {:ok, build_layers(dag, indeg, [])}
  end

  @doc """
  Returns the direct predecessors (incoming neighbours) of `vertex`.

  Returns `[]` if the vertex is absent. The result is sorted by term ordering.
  """
  @spec predecessors(t, vertex) :: [vertex]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag |> predecessors_set(vertex) |> Enum.sort()
  end

  @doc """
  Returns the direct successors (outgoing neighbours) of `vertex`.

  Returns `[]` if the vertex is absent. The result is sorted by term ordering.
  """
  @spec successors(t, vertex) :: [vertex]
  def successors(%__MODULE__{} = dag, vertex) do
    dag |> successors_set(vertex) |> Enum.sort()
  end

  # -- Internal helpers -----------------------------------------------------

  @spec insert_edge(t, vertex, vertex) :: t
  defp insert_edge(dag, from, to) do
    %__MODULE__{
      dag
      | out: Map.update!(dag.out, from, &MapSet.put(&1, to)),
        in: Map.update!(dag.in, to, &MapSet.put(&1, from))
    }
  end

  @spec successors_set(t, vertex) :: MapSet.t(vertex)
  defp successors_set(dag, vertex), do: Map.get(dag.out, vertex, MapSet.new())

  @spec predecessors_set(t, vertex) :: MapSet.t(vertex)
  defp predecessors_set(dag, vertex), do: Map.get(dag.in, vertex, MapSet.new())

  # Returns a path (list of vertices) from `start` to `target` following out
  # edges, or `nil` if none exists. When `start == target` the path is
  # `[start]`, which lets self-loops be reported as cycles uniformly.
  @spec find_path(t, vertex, vertex) :: [vertex] | nil
  defp find_path(dag, start, target) do
    do_find_path(dag, start, target, MapSet.new())
  end

  @spec do_find_path(t, vertex, vertex, MapSet.t(vertex)) :: [vertex] | nil
  defp do_find_path(_dag, node, target, _visited) when node == target do
    [node]
  end

  defp do_find_path(dag, node, target, visited) do
    if MapSet.member?(visited, node) do
      nil
    else
      visited = MapSet.put(visited, node)

      dag
      |> successors_set(node)
      |> Enum.find_value(fn succ ->
        case do_find_path(dag, succ, target, visited) do
          nil -> nil
          path -> [node | path]
        end
      end)
    end
  end

  @spec build_layers(t, %{optional(vertex) => non_neg_integer}, [[vertex]]) :: [[vertex]]
  defp build_layers(_dag, indeg, acc) when map_size(indeg) == 0 do
    Enum.reverse(acc)
  end

  defp build_layers(dag, indeg, acc) do
    zero = for {v, 0} <- indeg, do: v
    layer = Enum.sort(zero)
    remaining = Map.drop(indeg, zero)

    next_indeg =
      Enum.reduce(zero, remaining, fn v, acc_in ->
        Enum.reduce(successors_set(dag, v), acc_in, fn s, inner ->
          Map.update!(inner, s, &(&1 - 1))
        end)
      end)

    build_layers(dag, next_indeg, [layer | acc])
  end
end