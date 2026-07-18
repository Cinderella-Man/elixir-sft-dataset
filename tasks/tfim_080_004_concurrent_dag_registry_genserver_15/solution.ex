  test "vertices may be arbitrary terms such as tuples, maps, strings and lists", %{server: s} do
    terms = [{:job, 1}, %{id: "m"}, "build", [1, 2, 3], 7]
    for v <- terms, do: assert(:ok = DAGServer.add_vertex(s, v))

    assert :ok = DAGServer.add_edge(s, {:job, 1}, %{id: "m"})
    assert :ok = DAGServer.add_edge(s, %{id: "m"}, "build")
    assert {:error, :cycle} = DAGServer.add_edge(s, "build", {:job, 1})

    assert Enum.sort(DAGServer.vertices(s)) == Enum.sort(terms)
    assert DAGServer.successors(s, {:job, 1}) == [%{id: "m"}]
    assert DAGServer.predecessors(s, "build") == [%{id: "m"}]

    assert {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 5
    assert valid_topological_order?(order, [{{:job, 1}, %{id: "m"}}, {%{id: "m"}, "build"}])
  end