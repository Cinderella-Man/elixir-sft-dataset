  test "add_edge success and linear sort", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    :ok = DAGServer.add_vertex(s, :b)
    :ok = DAGServer.add_vertex(s, :c)
    assert :ok = DAGServer.add_edge(s, :a, :b)
    assert :ok = DAGServer.add_edge(s, :b, :c)
    assert {:ok, [:a, :b, :c]} = DAGServer.topological_sort(s)
  end