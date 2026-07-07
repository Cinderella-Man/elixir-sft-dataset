  test "topological sort remains valid on the diamond" do
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    dag = build([{:a, 3}, {:b, 2}, {:c, 5}, {:d, 1}], edges)

    assert {:ok, order} = WeightedDAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end