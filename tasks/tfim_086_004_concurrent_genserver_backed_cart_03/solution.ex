  test "add_item accumulates and validates quantity" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 3, 5.0)
    :ok = CartServer.add_item(pid, "a", 4, 5.0)
    [item] = CartServer.totals(pid).items
    assert item.quantity == 7
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 0, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", -2, 5.0)
  end