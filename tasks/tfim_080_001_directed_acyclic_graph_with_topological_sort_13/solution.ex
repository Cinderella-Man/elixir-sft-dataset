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