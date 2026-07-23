defmodule MutableDAG do
  @moduledoc """
  A mutable Directed Acyclic Graph (DAG) implemented as a pure data structure.

  Every operation takes a `%MutableDAG{}` struct and returns either an updated
  struct or a result tuple; there is no process or mutable state involved.

  The structure supports:

    * mutation — adding and removing both vertices and edges;
    * eager cycle diagnostics — `add_edge/3` refuses edges that would introduce a
      cycle and reports the actual offending path via a depth-first search;
    * parallel-execution layers — `topological_layers/1` groups vertices into
      "waves" that share no ordering constraints and could run concurrently.

  Vertices may be any Elixir term. Internally the graph keeps a set of vertices
  plus outgoing and incoming adjacency maps (vertex => `MapSet` of neighbours)
  so that both directions can be queried and mutated efficiently.
  """

  @typedoc "A vertex, which may be any term."
  @type vertex :: term()

  @typedoc "An adjacency map from a vertex to its neighbour set."
  @type adjacency :: %{optional(vertex()) => MapSet.t(vertex())}

  @typedoc "The DAG structure."
  @type t :: %__MODULE__{
          vertices: MapSet.t(vertex()),
          outgoing: adjacency(),
          incoming: adjacency()
        }

  defstruct vertices: MapSet.new(), outgoing: %{}, incoming: %{}

  @doc """
  Returns a new, empty DAG.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds `vertex` to `dag`.

  If the vertex already exists, `dag` is returned unchanged.
  """
  @spec add_vertex(t(), vertex()) :: t()
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if vertex?(dag, vertex) do
      dag
    else
      %{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          outgoing: Map.put(dag.outgoing, vertex, MapSet.new()),
          incoming: Map.put(dag.incoming, vertex, MapSet.new())
      }
    end
  end

  @doc """
  Adds a directed edge `from -> to`.

  Both endpoints must already exist; otherwise `{:error, :vertex_not_found}` is
  returned. If the edge would introduce a cycle, `{:error, {:cycle, path}}` is
  returned, where `path` is the list of vertices forming the cycle, starting and
  ending with `from`. A self-loop yields `{:error, {:cycle, [from, from]}}`.

  On success `{:ok, new_dag}` is returned.
  """
  @spec add_edge(t(), vertex(), vertex()) ::
          {:ok, t()} | {:error, {:cycle, [vertex()]}} | {:error, :vertex_not_found}
  def add_edge(%__MODULE__{} = dag, from, to) do
    cond do
      not vertex?(dag, from) or not vertex?(dag, to) ->
        {:error, :vertex_not_found}

      from == to ->
        {:error, {:cycle, [from, from]}}

      true ->
        case find_path(dag, to, from) do
          nil -> {:ok, put_edge(dag, from, to)}
          path -> {:error, {:cycle, [from | path]}}
        end
    end
  end

  @doc """
  Removes the directed edge `from -> to` if it is present.

  If the edge or either vertex is absent, `dag` is returned unchanged.
  """
  @spec remove_edge(t(), vertex(), vertex()) :: t()
  def remove_edge(%__MODULE__{} = dag, from, to) do
    if edge?(dag, from, to) do
      %{
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

  If the vertex is absent, `dag` is returned unchanged.
  """
  @spec remove_vertex(t(), vertex()) :: t()
  def remove_vertex(%__MODULE__{} = dag, vertex) do
    if vertex?(dag, vertex) do
      successors = Map.fetch!(dag.outgoing, vertex)
      predecessors = Map.fetch!(dag.incoming, vertex)

      incoming =
        Enum.reduce(successors, dag.incoming, fn s, acc ->
          Map.update!(acc, s, &MapSet.delete(&1, vertex))
        end)

      outgoing =
        Enum.reduce(predecessors, dag.outgoing, fn p, acc ->
          Map.update!(acc, p, &MapSet.delete(&1, vertex))
        end)

      %{
        dag
        | vertices: MapSet.delete(dag.vertices, vertex),
          outgoing: Map.delete(outgoing, vertex),
          incoming: Map.delete(incoming, vertex)
      }
    else
      dag
    end
  end

  @doc """
  Returns `{:ok, ordering}` — a flat list of every vertex in a valid topological
  order. Returns `{:ok, []}` for an empty graph.
  """
  @spec topological_sort(t()) :: {:ok, [vertex()]}
  def topological_sort(%__MODULE__{} = dag) do
    {:ok, layers} = topological_layers(dag)
    {:ok, Enum.concat(layers)}
  end

  @doc """
  Returns `{:ok, layers}`, a list of lists grouping vertices into execution
  waves.

  Layer 0 holds every vertex with no predecessors; each later layer holds the
  vertices whose predecessors have all appeared in earlier layers. Vertices
  within a layer are sorted by term ordering for determinism. Returns
  `{:ok, []}` for an empty graph.
  """
  @spec topological_layers(t()) :: {:ok, [[vertex()]]}
  def topological_layers(%__MODULE__{} = dag) do
    {:ok, collect_layers(dag, dag.vertices, [])}
  end

  @doc """
  Returns the direct predecessors (incoming neighbours) of `vertex`, sorted by
  term ordering. Returns `[]` when the vertex is absent.
  """
  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.incoming |> Map.get(vertex, MapSet.new()) |> Enum.sort()
  end

  @doc """
  Returns the direct successors (outgoing neighbours) of `vertex`, sorted by
  term ordering. Returns `[]` when the vertex is absent.
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.outgoing |> Map.get(vertex, MapSet.new()) |> Enum.sort()
  end

  # -- internal helpers ------------------------------------------------------

  @spec vertex?(t(), vertex()) :: boolean()
  defp vertex?(dag, vertex), do: MapSet.member?(dag.vertices, vertex)

  @spec edge?(t(), vertex(), vertex()) :: boolean()
  defp edge?(dag, from, to) do
    vertex?(dag, from) and vertex?(dag, to) and
      MapSet.member?(Map.fetch!(dag.outgoing, from), to)
  end

  @spec put_edge(t(), vertex(), vertex()) :: t()
  defp put_edge(dag, from, to) do
    %{
      dag
      | outgoing: Map.update!(dag.outgoing, from, &MapSet.put(&1, to)),
        incoming: Map.update!(dag.incoming, to, &MapSet.put(&1, from))
    }
  end

  # DFS for a path from `node` to `target` along existing outgoing edges.
  # Returns the path as a list starting with `node` and ending with `target`,
  # or `nil` if no such path exists.
  @spec find_path(t(), vertex(), vertex(), MapSet.t(vertex())) :: [vertex()] | nil
  defp find_path(dag, node, target, visited \\ MapSet.new()) do
    cond do
      node == target ->
        [node]

      MapSet.member?(visited, node) ->
        nil

      true ->
        seen = MapSet.put(visited, node)

        dag.outgoing
        |> Map.fetch!(node)
        |> Enum.sort()
        |> Enum.find_value(fn next ->
          case find_path(dag, next, target, seen) do
            nil -> nil
            path -> [node | path]
          end
        end)
    end
  end

  @spec collect_layers(t(), MapSet.t(vertex()), [[vertex()]]) :: [[vertex()]]
  defp collect_layers(dag, remaining, acc) do
    if MapSet.size(remaining) == 0 do
      Enum.reverse(acc)
    else
      layer =
        remaining
        |> Enum.filter(&ready?(dag, &1, remaining))
        |> Enum.sort()

      rest = MapSet.difference(remaining, MapSet.new(layer))
      collect_layers(dag, rest, [layer | acc])
    end
  end

  # A vertex is ready for the current layer when none of its predecessors are
  # still waiting in `remaining`.
  @spec ready?(t(), vertex(), MapSet.t(vertex())) :: boolean()
  defp ready?(dag, vertex, remaining) do
    MapSet.disjoint?(Map.fetch!(dag.incoming, vertex), remaining)
  end
end