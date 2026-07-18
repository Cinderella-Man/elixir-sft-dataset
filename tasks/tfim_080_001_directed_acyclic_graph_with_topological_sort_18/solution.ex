  test "add_edge/3 does not succeed when either endpoint is missing" do
    dag = DAG.new() |> DAG.add_vertex(:a)

    refute match?({:ok, _}, DAG.add_edge(dag, :a, :ghost))
    refute match?({:ok, _}, DAG.add_edge(dag, :ghost, :a))

    assert {:ok, [:a]} = DAG.topological_sort(dag)
    assert DAG.successors(dag, :a) == []
    assert DAG.predecessors(dag, :a) == []
  end