  test "diamond graph picks the heavier branch as critical path" do
    #        a(3)
    #       /    \
    #    b(2)    c(5)
    #       \    /
    #        d(1)
    dag =
      build(
        [{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}],
        [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
      )

    assert {:ok, est} = WeightedDAG.earliest_start(dag)
    assert est == %{a: 0, b: 3, c: 3, d: 8}

    assert {:ok, 9} = WeightedDAG.makespan(dag)
    assert {:ok, [:a, :c, :d]} = WeightedDAG.critical_path(dag)
  end