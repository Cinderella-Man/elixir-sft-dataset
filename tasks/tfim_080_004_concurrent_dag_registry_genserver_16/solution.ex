  test "sort includes isolated vertices and orders a diamond validly", %{server: s} do
    for v <- [:a, :b, :c, :d, :lonely], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :a, :c)
    :ok = DAGServer.add_edge(s, :b, :d)
    :ok = DAGServer.add_edge(s, :c, :d)

    assert {:ok, order} = DAGServer.topological_sort(s)
    assert Enum.sort(order) == [:a, :b, :c, :d, :lonely]
    assert length(order) == 5
    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    assert valid_topological_order?(order, edges)
  end