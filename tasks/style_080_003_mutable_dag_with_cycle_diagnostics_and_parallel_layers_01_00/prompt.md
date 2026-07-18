# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `MutableDAG` that implements a Directed Acyclic Graph supporting **mutation** (edge and vertex removal), **cycle diagnostics** (reporting the actual offending cycle path), and **parallel-execution layers**. It should be a pure data structure (no GenServer), where each function takes and returns a `MutableDAG` struct (or a result tuple).

I need these functions in the public API:
- `MutableDAG.new()` — returns an empty DAG.
- `MutableDAG.add_vertex(dag, vertex)` — adds a vertex; if it already exists, return the dag unchanged. Vertices can be any term.
- `MutableDAG.add_edge(dag, from, to)` — adds a directed edge. Both vertices must exist. If the edge would create a cycle, return `{:error, {:cycle, path}}` where `path` is the list of vertices forming the cycle, **starting and ending with `from`** (e.g. adding `c -> a` when `a -> b -> c` already exists returns `{:error, {:cycle, [c, a, b, c]}}`). A self-loop `add_edge(dag, a, a)` returns `{:error, {:cycle, [a, a]}}`. On success return `{:ok, new_dag}`. Detection must be eager (DFS path search).
- `MutableDAG.remove_edge(dag, from, to)` — removes the directed edge if present; if the edge or either vertex is absent, return the dag unchanged.
- `MutableDAG.remove_vertex(dag, vertex)` — removes the vertex and every edge incident to it (both incoming and outgoing); if absent, return the dag unchanged.
- `MutableDAG.topological_sort(dag)` — returns `{:ok, ordering}`, a flat list of all vertices in a valid topological order. `{:ok, []}` for an empty graph.
- `MutableDAG.topological_layers(dag)` — returns `{:ok, layers}` where `layers` is a list of lists. Layer 0 contains every vertex with no predecessors; each subsequent layer contains the vertices whose predecessors have all appeared in earlier layers. This groups vertices into "waves" that could execute in parallel. Sort the vertices **within each layer** by term ordering for determinism. `{:ok, []}` for an empty graph.
- `MutableDAG.predecessors(dag, vertex)` / `MutableDAG.successors(dag, vertex)` — direct incoming / outgoing neighbours.

Give me the complete module in a single file. Use only the Elixir/Erlang standard library, no external dependencies.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  @spec new() :: t()
  def new, do: %__MODULE__{}

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

  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  @spec topological_layers(t()) :: {:ok, [[vertex()]]}
  def topological_layers(%__MODULE__{} = dag) do
    in_degree =
      Map.new(dag.vertices, fn v -> {v, MapSet.size(Map.fetch!(dag.in_edges, v))} end)

    {:ok, build_layers(in_degree, dag.out_edges, [])}
  end

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

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/080_003_mutable_dag_with_cycle_diagnostics_and_parallel_layers_01/attempt_0 -->
