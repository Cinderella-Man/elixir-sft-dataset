  test "missing vertex is rejected", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :a, :ghost)
  end