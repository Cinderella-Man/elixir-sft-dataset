  test "duplicate vertices are ignored" do
    dag =
      MutableDAG.new()
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b]
  end