defmodule DAGTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Checks that every vertex in `edges` appears before its dependent
  # in the given ordering list.
  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 returns an empty DAG" do
    dag = DAG.new()
    assert {:ok, []} = DAG.topological_sort(dag)
  end

  test "add_vertex/2 adds vertices; duplicates are ignored" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:a)

    {:ok, order} = DAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b]
  end

  test "add_edge/3 returns {:ok, dag} on success" do
    dag = DAG.new() |> DAG.add_vertex(:a) |> DAG.add_vertex(:b)
    assert {:ok, _dag} = DAG.add_edge(dag, :a, :b)
  end

  # -------------------------------------------------------
  # Cycle detection
  # -------------------------------------------------------

  test "direct cycle (a -> b -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    assert {:error, :cycle} = DAG.add_edge(dag, :b, :a)
  end

  test "self-loop (a -> a) is rejected" do
    dag = DAG.new() |> DAG.add_vertex(:a)
    assert {:error, :cycle} = DAG.add_edge(dag, :a, :a)
  end

  test "indirect cycle (a -> b -> c -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)
    assert {:error, :cycle} = DAG.add_edge(dag, :c, :a)
  end

  test "non-cycle-forming edges are all accepted" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)
      |> DAG.add_vertex(:d)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :d)
    {:ok, _dag} = DAG.add_edge(dag, :c, :d)
  end

  # -------------------------------------------------------
  # Topological sort
  # -------------------------------------------------------

  test "topological sort of a linear chain" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert order == [:a, :b, :c]
  end

  test "topological sort is valid for a diamond graph" do
    #     a
    #    / \
    #   b   c
    #    \ /
    #     d
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)
      |> DAG.add_vertex(:d)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :d)
    {:ok, dag} = DAG.add_edge(dag, :c, :d)

    assert {:ok, order} = DAG.topological_sort(dag)

    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end

  test "topological sort includes isolated vertices" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:isolated)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert :isolated in order
    assert length(order) == 3
  end

  test "topological sort is valid for a known dependency graph" do
    # Simulates: mix -> hex -> ssl -> crypto
    #                        -> public_key -> crypto
    vertices = [:mix, :hex, :ssl, :crypto, :public_key]

    edges = [
      {:mix, :hex},
      {:hex, :ssl},
      {:ssl, :crypto},
      {:ssl, :public_key},
      {:public_key, :crypto}
    ]

    dag = Enum.reduce(vertices, DAG.new(), &DAG.add_vertex(&2, &1))

    dag =
      Enum.reduce(edges, dag, fn {from, to}, acc ->
        {:ok, updated} = DAG.add_edge(acc, from, to)
        updated
      end)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == length(vertices)
  end

  # -------------------------------------------------------
  # Predecessors & successors
  # -------------------------------------------------------

  test "successors/2 returns direct outgoing neighbours" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)

    assert Enum.sort(DAG.successors(dag, :a)) == [:b, :c]
    assert DAG.successors(dag, :b) == []
  end

  test "predecessors/2 returns direct incoming neighbours" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)

    assert Enum.sort(DAG.predecessors(dag, :c)) == [:a, :b]
    assert DAG.predecessors(dag, :a) == []
  end

  test "predecessors and successors are consistent with each other" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:x)
      |> DAG.add_vertex(:y)
      |> DAG.add_vertex(:z)

    {:ok, dag} = DAG.add_edge(dag, :x, :y)
    {:ok, dag} = DAG.add_edge(dag, :x, :z)

    assert :x in DAG.predecessors(dag, :y)
    assert :x in DAG.predecessors(dag, :z)
    assert :y in DAG.successors(dag, :x)
    assert :z in DAG.successors(dag, :x)
  end
end
