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