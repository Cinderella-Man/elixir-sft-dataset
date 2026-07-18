  test "missing source endpoint is rejected just like a missing target", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)

    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :ghost, :a)
    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :ghost, :phantom)

    assert DAGServer.vertices(s) == [:a]
    assert DAGServer.predecessors(s, :a) == []
  end