  test "predecessors and successors" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :c}, {:b, :c}])

    assert Enum.sort(WeightedDAG.predecessors(dag, :c)) == [:a, :b]
    assert WeightedDAG.successors(dag, :a) == [:c]
    assert WeightedDAG.successors(dag, :c) == []
  end