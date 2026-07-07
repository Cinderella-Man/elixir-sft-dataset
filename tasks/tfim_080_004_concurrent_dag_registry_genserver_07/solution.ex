  test "indirect cycle rejected", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)
    assert {:error, :cycle} = DAGServer.add_edge(s, :c, :a)
  end