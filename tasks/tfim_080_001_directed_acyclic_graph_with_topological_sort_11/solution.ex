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