  test "remove_vertex drops incident edges" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])
    dag = MutableDAG.remove_vertex(dag, :b)

    {:ok, order} = MutableDAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :c, :d]
    assert MutableDAG.successors(dag, :a) == [:c]
    assert MutableDAG.predecessors(dag, :d) == [:c]
  end