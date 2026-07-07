  test "predecessors and successors", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :c)
    :ok = DAGServer.add_edge(s, :b, :c)
    assert Enum.sort(DAGServer.predecessors(s, :c)) == [:a, :b]
    assert DAGServer.successors(s, :a) == [:c]
    assert DAGServer.successors(s, :c) == []
  end