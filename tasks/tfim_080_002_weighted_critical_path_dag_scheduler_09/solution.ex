  test "isolated task participates in makespan" do
    dag = build([{:a, 2}, {:iso, 10}, {:b, 3}], [{:a, :b}])

    assert {:ok, order} = WeightedDAG.topological_sort(dag)
    assert :iso in order
    assert {:ok, 10} = WeightedDAG.makespan(dag)
    assert {:ok, [:iso]} = WeightedDAG.critical_path(dag)
  end