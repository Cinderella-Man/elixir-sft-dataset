  test "add_vertex is idempotent", %{server: s} do
    assert :ok = DAGServer.add_vertex(s, :a)
    assert :ok = DAGServer.add_vertex(s, :a)
    assert :ok = DAGServer.add_vertex(s, :b)
    assert Enum.sort(DAGServer.vertices(s)) == [:a, :b]
  end