  test "empty graph: sort, makespan, critical path" do
    dag = WeightedDAG.new()
    assert {:ok, []} = WeightedDAG.topological_sort(dag)
    assert {:ok, 0} = WeightedDAG.makespan(dag)
    assert {:ok, []} = WeightedDAG.critical_path(dag)
  end