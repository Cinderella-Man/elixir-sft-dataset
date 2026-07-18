  test "remove_edge of absent edge is a no-op" do
    dag = build([:a, :b], [{:a, :b}])
    same = MutableDAG.remove_edge(dag, :b, :a)
    assert MutableDAG.successors(same, :a) == [:b]
  end