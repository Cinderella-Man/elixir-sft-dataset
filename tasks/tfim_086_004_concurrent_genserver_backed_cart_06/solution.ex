  test "concurrent adds to the same product accumulate with no lost updates" do
    {:ok, pid} = CartServer.start_link()

    1..100
    |> Enum.map(fn _ -> Task.async(fn -> CartServer.add_item(pid, "p", 1, 2.0) end) end)
    |> Task.await_many(5000)

    [item] = CartServer.totals(pid).items
    assert item.quantity == 100
    # quantity 100 >= 10 triggers the 10% bulk discount: 2.0 * 0.9 * 100 = 180.0
    assert_in_delta CartServer.totals(pid).subtotal, 180.0, 0.001
  end