# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MutableDAGTest do
  use ExUnit.Case, async: false

  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  defp build(vertices, edges) do
    dag = Enum.reduce(vertices, MutableDAG.new(), &MutableDAG.add_vertex(&2, &1))

    Enum.reduce(edges, dag, fn {from, to}, acc ->
      {:ok, updated} = MutableDAG.add_edge(acc, from, to)
      updated
    end)
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "empty graph" do
    dag = MutableDAG.new()
    assert {:ok, []} = MutableDAG.topological_sort(dag)
    assert {:ok, []} = MutableDAG.topological_layers(dag)
  end

  test "duplicate vertices are ignored" do
    dag =
      MutableDAG.new()
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b]
  end

  # -------------------------------------------------------
  # Cycle diagnostics
  # -------------------------------------------------------

  test "self-loop reports [a, a]" do
    dag = MutableDAG.new() |> MutableDAG.add_vertex(:a)
    assert {:error, {:cycle, [:a, :a]}} = MutableDAG.add_edge(dag, :a, :a)
  end

  test "cycle-forming edge reports the offending path from->...->from" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    assert {:error, {:cycle, [:c, :a, :b, :c]}} = MutableDAG.add_edge(dag, :c, :a)
  end

  test "direct back edge reports two-hop cycle" do
    dag = build([:a, :b], [{:a, :b}])
    assert {:error, {:cycle, [:b, :a, :b]}} = MutableDAG.add_edge(dag, :b, :a)
  end

  test "missing vertex is rejected" do
    dag = MutableDAG.new() |> MutableDAG.add_vertex(:a)
    assert {:error, :vertex_not_found} = MutableDAG.add_edge(dag, :a, :ghost)
  end

  # -------------------------------------------------------
  # Parallel layers
  # -------------------------------------------------------

  test "diamond graph groups into parallel waves" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])
    assert {:ok, [[:a], [:b, :c], [:d]]} = MutableDAG.topological_layers(dag)
  end

  test "isolated vertices sit in layer 0" do
    # TODO
  end

  test "flat topological sort is consistent with edges" do
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    dag = build([:a, :b, :c, :d], edges)
    {:ok, order} = MutableDAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end

  # -------------------------------------------------------
  # Mutation: remove_edge
  # -------------------------------------------------------

  test "remove_edge detaches a dependency" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    dag = MutableDAG.remove_edge(dag, :b, :c)

    assert MutableDAG.successors(dag, :b) == []
    assert MutableDAG.predecessors(dag, :c) == []
    assert {:ok, [[:a, :c], [:b]]} = MutableDAG.topological_layers(dag)
  end

  test "remove_edge of absent edge is a no-op" do
    dag = build([:a, :b], [{:a, :b}])
    same = MutableDAG.remove_edge(dag, :b, :a)
    assert MutableDAG.successors(same, :a) == [:b]
  end

  test "remove_edge lets a previously-cyclic edge succeed" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    assert {:error, {:cycle, _}} = MutableDAG.add_edge(dag, :c, :a)

    dag = MutableDAG.remove_edge(dag, :b, :c)
    assert {:ok, _dag} = MutableDAG.add_edge(dag, :c, :a)
  end

  # -------------------------------------------------------
  # Mutation: remove_vertex
  # -------------------------------------------------------

  test "remove_vertex drops incident edges" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])
    dag = MutableDAG.remove_vertex(dag, :b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :c, :d]
    assert MutableDAG.successors(dag, :a) == [:c]
    assert MutableDAG.predecessors(dag, :d) == [:c]
  end

  test "remove_vertex of absent vertex is a no-op" do
    dag = build([:a, :b], [{:a, :b}])
    same = MutableDAG.remove_vertex(dag, :ghost)
    {:ok, order} = MutableDAG.topological_sort(same)
    assert Enum.sort(order) == [:a, :b]
  end
end
```
