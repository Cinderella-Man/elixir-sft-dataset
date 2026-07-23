# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `reach_path` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Hey — I need a piece of graph plumbing built and I'd rather describe it than write it myself, so here's exactly what I'm after.

I want an Elixir module called `MutableDAG`: a Directed Acyclic Graph that supports **mutation** (removing edges and vertices), **cycle diagnostics** (it has to tell me the actual offending cycle path, not just "nope"), and **parallel-execution layers**. Keep it a pure data structure — no GenServer anywhere. Every function takes a `MutableDAG` struct and hands back a `MutableDAG` struct (or a result tuple).

The public API I'm counting on:

`MutableDAG.new()` — gives me an empty DAG.

`MutableDAG.add_vertex(dag, vertex)` — adds a vertex; if it's already in there, just return the dag unchanged. Vertices can be any term, so don't constrain them.

`MutableDAG.add_edge(dag, from, to)` — adds a directed edge. Both vertices have to exist already. If the edge would create a cycle, I want `{:error, {:cycle, path}}` back, where `path` is the list of vertices making up the cycle, **starting and ending with `from`** — so if `a -> b -> c` is already in the graph and I try to add `c -> a`, I expect `{:error, {:cycle, [c, a, b, c]}}`. A self-loop, `add_edge(dag, a, a)`, should come back as `{:error, {:cycle, [a, a]}}`. When it works, return `{:ok, new_dag}`. The detection needs to be eager — do a DFS path search at insert time.

`MutableDAG.remove_edge(dag, from, to)` — drops the directed edge if it's there; if the edge is missing, or either vertex is missing, return the dag unchanged.

`MutableDAG.remove_vertex(dag, vertex)` — removes the vertex along with every edge incident to it, both incoming and outgoing; if the vertex isn't present, return the dag unchanged.

`MutableDAG.topological_sort(dag)` — returns `{:ok, ordering}`, a flat list of all the vertices in a valid topological order. An empty graph gives `{:ok, []}`.

`MutableDAG.topological_layers(dag)` — returns `{:ok, layers}`, where `layers` is a list of lists. Layer 0 holds every vertex with no predecessors; each layer after that holds the vertices whose predecessors have all already shown up in earlier layers. That's the grouping I want — "waves" of vertices that could run in parallel. Sort the vertices **within each layer** by term ordering so the output is deterministic. Empty graph gives `{:ok, []}`.

`MutableDAG.predecessors(dag, vertex)` and `MutableDAG.successors(dag, vertex)` — the direct incoming and outgoing neighbours respectively.

One more bit of the interface contract I care about: `add_edge(dag, from, to)` must return exactly `{:error, :vertex_not_found}` when either endpoint (`from` or `to`) hasn't been added as a vertex.

Please send me the complete module in a single file, and stick to the Elixir/Erlang standard library — no external dependencies.

## The module with `reach_path` missing

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
    if map_size(in_degree) == 0 do
      Enum.reverse(acc)
    else
      layer =
        in_degree
        |> Enum.filter(fn {_v, d} -> d == 0 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      remaining = Map.drop(in_degree, layer)

      new_in_degree =
        Enum.reduce(layer, remaining, fn v, deg ->
          Enum.reduce(Map.get(out_edges, v, MapSet.new()), deg, fn s, d ->
            Map.update!(d, s, &(&1 - 1))
          end)
        end)

      build_layers(new_in_degree, out_edges, [layer | acc])
    end
  end

  defp require_vertex(dag, vertex) do
    if MapSet.member?(dag.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end

  defp reach_path(out_edges, current, target) do
    # TODO
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

Give me only the complete implementation of `reach_path` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
