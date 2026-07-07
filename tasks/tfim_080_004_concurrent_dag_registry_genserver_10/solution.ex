  test "concurrent chain edges stay acyclic and consistent", %{server: s} do
    for i <- 1..50, do: :ok = DAGServer.add_vertex(s, i)

    results =
      1..49
      |> Enum.map(fn i -> Task.async(fn -> DAGServer.add_edge(s, i, i + 1) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == :ok))

    {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 50
    assert order == Enum.to_list(1..50)

    edges = for i <- 1..49, do: {i, i + 1}
    assert valid_topological_order?(order, edges)
  end