  test "flat topological sort is consistent with edges" do
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    dag = build([:a, :b, :c, :d], edges)
    {:ok, order} = MutableDAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end