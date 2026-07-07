  test "linear chain earliest start / finish / makespan / critical path" do
    dag = build([{:a, 3}, {:b, 2}, {:c, 4}], [{:a, :b}, {:b, :c}])

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 5}

    assert {:ok, eft} = WeightedDAG.earliest_finish(dag)
    assert eft == %{a: 3, b: 5, c: 9}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :b, :c]} = WeightedDAG.critical_path(dag)
  end