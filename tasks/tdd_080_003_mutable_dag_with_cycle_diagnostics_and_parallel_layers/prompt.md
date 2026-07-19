# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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

  test "re-adding a vertex that already has edges keeps those edges" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])

    dag =
      dag
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:b)
      |> MutableDAG.add_vertex(:d)

    assert Enum.sort(MutableDAG.successors(dag, :a)) == [:b, :c]
    assert Enum.sort(MutableDAG.predecessors(dag, :d)) == [:b, :c]
    assert MutableDAG.successors(dag, :b) == [:d]
    assert MutableDAG.predecessors(dag, :b) == [:a]
    assert {:ok, [[:a], [:b, :c], [:d]]} = MutableDAG.topological_layers(dag)
  end

  test "re-adding a vertex leaves the topological order intact" do
    edges = [{:a, :b}, {:b, :c}]
    dag = build([:a, :b, :c], edges)

    dag = MutableDAG.add_vertex(dag, :b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b, :c]
    assert valid_topological_order?(order, edges)
  end

  test "re-adding a vertex does not reopen a cycle-forming edge" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    dag = MutableDAG.add_vertex(dag, :b)

    assert {:error, {:cycle, [:c, :a, :b, :c]}} = MutableDAG.add_edge(dag, :c, :a)
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
    dag = build([:a, :b, :iso], [{:a, :b}])
    assert {:ok, [[:a, :iso], [:b]]} = MutableDAG.topological_layers(dag)
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

  test "a removed vertex can be re-added as a fresh isolated vertex" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])

    dag =
      dag
      |> MutableDAG.remove_vertex(:b)
      |> MutableDAG.add_vertex(:b)

    assert MutableDAG.successors(dag, :b) == []
    assert MutableDAG.predecessors(dag, :b) == []
    assert MutableDAG.successors(dag, :a) == []
    assert MutableDAG.predecessors(dag, :c) == []
    assert {:ok, [[:a, :b, :c]]} = MutableDAG.topological_layers(dag)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
