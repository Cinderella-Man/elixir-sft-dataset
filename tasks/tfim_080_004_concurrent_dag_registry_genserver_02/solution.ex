  test "empty graph sorts to []", %{server: s} do
    assert {:ok, []} = DAGServer.topological_sort(s)
    assert DAGServer.vertices(s) == []
  end