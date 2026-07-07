  test "diamond graph groups into parallel waves" do
    dag = build([:a, :b, :c, :d], [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])
    assert {:ok, [[:a], [:b, :c], [:d]]} = MutableDAG.topological_layers(dag)
  end