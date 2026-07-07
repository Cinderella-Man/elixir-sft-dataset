  test "concurrent add_vertex from many processes lands consistently", %{server: s} do
    1..100
    |> Enum.map(fn i -> Task.async(fn -> DAGServer.add_vertex(s, i) end) end)
    |> Enum.each(&Task.await/1)

    assert Enum.sort(DAGServer.vertices(s)) == Enum.to_list(1..100)
  end