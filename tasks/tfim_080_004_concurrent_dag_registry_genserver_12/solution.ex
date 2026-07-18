  test "rejected cycle edge is not committed to the graph", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)

    assert {:error, :cycle} = DAGServer.add_edge(s, :c, :a)

    assert DAGServer.successors(s, :c) == []
    assert DAGServer.predecessors(s, :a) == []
    assert {:ok, order} = DAGServer.topological_sort(s)
    assert order == [:a, :b, :c]
    assert valid_topological_order?(order, [{:a, :b}, {:b, :c}])
  end