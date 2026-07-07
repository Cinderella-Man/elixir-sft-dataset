  test "non-cycle-forming edges are all accepted" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)
      |> DAG.add_vertex(:d)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :d)
    {:ok, _dag} = DAG.add_edge(dag, :c, :d)
  end