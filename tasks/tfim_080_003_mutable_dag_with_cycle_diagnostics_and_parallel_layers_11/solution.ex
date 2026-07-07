  test "remove_edge detaches a dependency" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    dag = MutableDAG.remove_edge(dag, :b, :c)

    assert MutableDAG.successors(dag, :b) == []
    assert MutableDAG.predecessors(dag, :c) == []
    assert {:ok, [[:a, :c], [:b]]} = MutableDAG.topological_layers(dag)
  end