  test "re-adding an existing vertex preserves its existing edges" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)

    re_added = dag |> DAG.add_vertex(:a) |> DAG.add_vertex(:b)

    assert re_added == dag
    assert DAG.successors(re_added, :a) == [:b]
    assert DAG.predecessors(re_added, :b) == [:a]
    assert {:ok, [:a, :b]} = DAG.topological_sort(re_added)
  end