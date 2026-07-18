  test "re-adding a vertex leaves the topological order intact" do
    edges = [{:a, :b}, {:b, :c}]
    dag = build([:a, :b, :c], edges)

    dag = MutableDAG.add_vertex(dag, :b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b, :c]
    assert valid_topological_order?(order, edges)
  end