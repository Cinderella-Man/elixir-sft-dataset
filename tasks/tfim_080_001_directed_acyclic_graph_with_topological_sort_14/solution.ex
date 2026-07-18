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