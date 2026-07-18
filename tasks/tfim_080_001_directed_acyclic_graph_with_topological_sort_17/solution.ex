  test "an edge rejected as a cycle leaves the graph completely unmodified" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)

    assert {:error, :cycle} = DAG.add_edge(dag, :c, :a)

    assert DAG.successors(dag, :c) == []
    assert DAG.predecessors(dag, :a) == []
    assert {:ok, [:a, :b, :c]} = DAG.topological_sort(dag)
  end