  test "remove_vertex of absent vertex is a no-op" do
    dag = build([:a, :b], [{:a, :b}])
    same = MutableDAG.remove_vertex(dag, :ghost)
    {:ok, order} = MutableDAG.topological_sort(same)
    assert Enum.sort(order) == [:a, :b]
  end