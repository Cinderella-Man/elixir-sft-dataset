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