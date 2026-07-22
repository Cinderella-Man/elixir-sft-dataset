# Fill in the middle: `MutableDAG.build_layers/3`

`MutableDAG` is a pure data-structure implementation of a mutable Directed
Acyclic Graph. The public `topological_layers/1` function computes the graph's
in-degree map and then delegates the actual layering work to the private
recursive helper `build_layers/3`. Your job is to implement that helper.

## What `build_layers/3` must do

Implement the private `build_layers(in_degree, out_edges, acc)` function. It
performs a layer-by-layer (Kahn's-algorithm-style) topological grouping and
returns a list of layers, where each layer is a list of vertices.

Arguments:
- `in_degree` — a map of `%{vertex => remaining_in_degree}` for every vertex
  not yet placed into a layer. A vertex's value is the number of its
  predecessors that have not yet appeared in an earlier layer.
- `out_edges` — the forward adjacency map `%{vertex => MapSet of successors}`.
- `acc` — the layers accumulated so far, stored in **reverse** order (most
  recent layer first).

Behaviour:
1. **Base case:** when `in_degree` is empty (`map_size == 0`), there is nothing
   left to place, so return `Enum.reverse(acc)` to restore chronological layer
   order.
2. **Recursive case:** otherwise
   - Build the next `layer` from every vertex in `in_degree` whose remaining
     in-degree is `0`. Sort these vertices by term ordering (`Enum.sort/1`) so
     the layer is deterministic.
   - Remove those vertices from the working in-degree map (e.g. with
     `Map.drop/2`).
   - For each vertex placed in `layer`, walk its successors from `out_edges`
     (defaulting to an empty `MapSet`) and decrement each successor's remaining
     in-degree by `1`.
   - Recurse with the updated in-degree map, the same `out_edges`, and the new
     `layer` prepended onto `acc`.

The whole module is reproduced below with the body of `build_layers/3` replaced
by `# TODO`. Every other function is intact.

```elixir
defmodule MutableDAG do
  @moduledoc """
  A mutable Directed Acyclic Graph.

  Beyond building and sorting, this variant supports:
    * edge and vertex **removal**;
    * **cycle diagnostics** — a rejected edge reports the actual offending
      cycle path (starting and ending with the `from` vertex);
    * **parallel-execution layers** — `topological_layers/1` groups vertices
      into dependency "waves" that could run concurrently.

  Internally the struct holds:
    * `vertices`  – a `MapSet` of all vertices (any term).
    * `out_edges` – `%{vertex => MapSet of successors}` (forward adjacency).
    * `in_edges`  – `%{vertex => MapSet of predecessors}` (reverse adjacency).
  """

  defstruct vertices: MapSet.new(), out_edges: %{}, in_edges: %{}

  @type vertex :: term()
  @type t :: %__MODULE__{
          vertices: MapSet.t(),
          out_edges: %{vertex() => MapSet.t()},
          in_edges: %{vertex() => MapSet.t()}
        }

  # ---------------------------------------------------------------------------
  # Construction / mutation
  # ---------------------------------------------------------------------------

  @doc """
  Returns a new, empty `MutableDAG`.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds `vertex` to `dag`.

  Vertices can be any term. If the vertex already exists the `dag` is
  returned unchanged.
  """
  @spec add_vertex(t(), vertex()) :: t()
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          out_edges: Map.put_new(dag.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, vertex, MapSet.new())
      }
    end
  end

  @doc """
  Adds a directed edge `from -> to`.

  Both vertices must already exist, otherwise `{:error, :vertex_not_found}`
  is returned. When the edge would introduce a cycle, returns
  `{:error, {:cycle, path}}` where `path` lists the vertices of the cycle,
  starting and ending with `from`. On success returns `{:ok, new_dag}`.
  """
  @spec add_edge(t(), vertex(), vertex()) ::
          {:ok, t()} | {:error, {:cycle, [vertex()]}} | {:error, :vertex_not_found}
  def add_edge(%__MODULE__{} = dag, from, to) do
    with :ok <- require_vertex(dag, from),
         :ok <- require_vertex(dag, to) do
      cond do
        from == to ->
          {:error, {:cycle, [from, from]}}

        true ->
          # Adding from->to closes a cycle iff `from` is already reachable
          # from `to`. reach_path returns [to, ..., from] when such a path
          # exists; prefixing `from` yields the full loop [from, to, ..., from].
          case reach_path(dag.out_edges, to, from) do
            nil ->
              new_dag = %{
                dag
                | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
                  in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
              }

              {:ok, new_dag}

            path ->
              {:error, {:cycle, [from | path]}}
          end
      end
    end
  end

  @doc """
  Removes the directed edge `from -> to` if present.

  If the edge or either vertex is absent, `dag` is returned unchanged.
  """
  @spec remove_edge(t(), vertex(), vertex()) :: t()
  def remove_edge(%__MODULE__{} = dag, from, to) do
    if MapSet.member?(dag.vertices, from) and MapSet.member?(dag.vertices, to) do
      %{
        dag
        | out_edges: Map.update(dag.out_edges, from, MapSet.new(), &MapSet.delete(&1, to)),
          in_edges: Map.update(dag.in_edges, to, MapSet.new(), &MapSet.delete(&1, from))
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
    if MapSet.member?(dag.vertices, vertex) do
      successors = Map.get(dag.out_edges, vertex, MapSet.new())
      predecessors = Map.get(dag.in_edges, vertex, MapSet.new())

      in_edges =
        Enum.reduce(successors, dag.in_edges, fn s, acc ->
          Map.update(acc, s, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      out_edges =
        Enum.reduce(predecessors, dag.out_edges, fn p, acc ->
          Map.update(acc, p, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      %{
        dag
        | vertices: MapSet.delete(dag.vertices, vertex),
          out_edges: Map.delete(out_edges, vertex),
          in_edges: Map.delete(in_edges, vertex)
      }
    else
      dag
    end
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc """
  Returns the direct predecessors (incoming neighbours) of `vertex`.
  """
  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  @doc """
  Returns the direct successors (outgoing neighbours) of `vertex`.
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  @doc """
  Groups every vertex into topological layers ("parallel waves").

  Layer 0 holds all vertices with no predecessors; each subsequent layer
  holds vertices whose predecessors have all appeared in earlier layers.
  Vertices within a layer are sorted by term ordering for determinism.
  Returns `{:ok, layers}`; an empty graph yields `{:ok, []}`.
  """
  @spec topological_layers(t()) :: {:ok, [[vertex()]]}
  def topological_layers(%__MODULE__{} = dag) do
    in_degree =
      Map.new(dag.vertices, fn v -> {v, MapSet.size(Map.fetch!(dag.in_edges, v))} end)

    {:ok, build_layers(in_degree, dag.out_edges, [])}
  end

  @doc """
  Returns `{:ok, ordering}`, a flat list of all vertices in a valid
  topological order. An empty graph yields `{:ok, []}`.
  """
  @spec topological_sort(t()) :: {:ok, [vertex()]}
  def topological_sort(%__MODULE__{} = dag) do
    {:ok, layers} = topological_layers(dag)
    {:ok, Enum.concat(layers)}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp build_layers(in_degree, out_edges, acc) do
    # TODO
  end

  defp require_vertex(dag, vertex) do
    if MapSet.member?(dag.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end

  # Returns a path [current, ..., target] following out_edges, or nil.
  defp reach_path(out_edges, current, target) do
    do_reach(out_edges, current, target, MapSet.new(), [])
  end

  defp do_reach(out_edges, current, target, visited, acc) do
    cond do
      current == target ->
        Enum.reverse([current | acc])

      MapSet.member?(visited, current) ->
        nil

      true ->
        visited = MapSet.put(visited, current)

        out_edges
        |> Map.get(current, MapSet.new())
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.find_value(fn neighbor ->
          do_reach(out_edges, neighbor, target, visited, [current | acc])
        end)
    end
  end
end
```