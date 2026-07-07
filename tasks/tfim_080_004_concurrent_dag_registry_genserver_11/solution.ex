  test "concurrent conflicting edges never form a cycle", %{server: s} do
    for v <- [:a, :b], do: :ok = DAGServer.add_vertex(s, v)

    results =
      [
        Task.async(fn -> DAGServer.add_edge(s, :a, :b) end),
        Task.async(fn -> DAGServer.add_edge(s, :b, :a) end)
      ]
      |> Enum.map(&Task.await/1)

    # Exactly one direction can succeed; the other must be rejected as a cycle.
    assert Enum.sort(results) == [:ok, {:error, :cycle}]
    assert {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 2
  end