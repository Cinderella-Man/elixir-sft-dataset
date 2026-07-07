  test "indirect cycle (a -> b -> c -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)
    assert {:error, :cycle} = DAG.add_edge(dag, :c, :a)
  end