  test "concurrent adds across distinct products all land" do
    {:ok, pid} = CartServer.start_link()

    1..50
    |> Enum.map(fn i -> Task.async(fn -> CartServer.add_item(pid, "p#{i}", 1, 1.0) end) end)
    |> Task.await_many(5000)

    assert length(CartServer.totals(pid).items) == 50
  end