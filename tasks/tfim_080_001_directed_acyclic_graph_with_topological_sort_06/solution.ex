  test "self-loop (a -> a) is rejected" do
    dag = DAG.new() |> DAG.add_vertex(:a)
    assert {:error, :cycle} = DAG.add_edge(dag, :a, :a)
  end