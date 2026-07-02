  test "add_edge/3 returns {:ok, dag} on success" do
    dag = DAG.new() |> DAG.add_vertex(:a) |> DAG.add_vertex(:b)
    assert {:ok, _dag} = DAG.add_edge(dag, :a, :b)
  end