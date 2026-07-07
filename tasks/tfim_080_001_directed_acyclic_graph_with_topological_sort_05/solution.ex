  test "direct cycle (a -> b -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    assert {:error, :cycle} = DAG.add_edge(dag, :b, :a)
  end