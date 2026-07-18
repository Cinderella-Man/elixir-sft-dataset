  test "neighbour queries report only direct edges, not transitive reachability", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)

    assert DAGServer.predecessors(s, :c) == [:b]
    assert DAGServer.successors(s, :a) == [:b]
    assert DAGServer.predecessors(s, :b) == [:a]
    assert DAGServer.successors(s, :b) == [:c]
  end