  test "re-adding a vertex that already has edges keeps those edges" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])

    dag =
      dag
      |> MutableDAG.add_vertex(:a)
      |> MutableDAG.add_vertex(:b)
      |> MutableDAG.add_vertex(:d)

    assert Enum.sort(MutableDAG.successors(dag, :a)) == [:b, :c]
    assert Enum.sort(MutableDAG.predecessors(dag, :d)) == [:b, :c]
    assert MutableDAG.successors(dag, :b) == [:d]
    assert MutableDAG.predecessors(dag, :b) == [:a]
    assert {:ok, [[:a], [:b, :c], [:d]]} = MutableDAG.topological_layers(dag)
  end