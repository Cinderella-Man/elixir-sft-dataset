  test "add_vertex/2 adds vertices; duplicates are ignored" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:a)

    {:ok, order} = DAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b]
  end