  test "self-loop and direct cycle rejected", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    :ok = DAGServer.add_vertex(s, :b)
    assert {:error, :cycle} = DAGServer.add_edge(s, :a, :a)
    :ok = DAGServer.add_edge(s, :a, :b)
    assert {:error, :cycle} = DAGServer.add_edge(s, :b, :a)
  end