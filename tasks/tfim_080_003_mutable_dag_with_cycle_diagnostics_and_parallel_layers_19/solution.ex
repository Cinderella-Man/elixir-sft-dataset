  test "a removed vertex can be re-added as a fresh isolated vertex" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])

    dag =
      dag
      |> MutableDAG.remove_vertex(:b)
      |> MutableDAG.add_vertex(:b)

    assert MutableDAG.successors(dag, :b) == []
    assert MutableDAG.predecessors(dag, :b) == []
    assert MutableDAG.successors(dag, :a) == []
    assert MutableDAG.predecessors(dag, :c) == []
    assert {:ok, [[:a, :b, :c]]} = MutableDAG.topological_layers(dag)
  end