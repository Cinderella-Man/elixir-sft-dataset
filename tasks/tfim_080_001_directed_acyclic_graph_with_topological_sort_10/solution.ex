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