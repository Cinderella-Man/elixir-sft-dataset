  test "remove_item and update_quantity" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 2, 5.0)
    :ok = CartServer.update_quantity(pid, "a", 8)
    [item] = CartServer.totals(pid).items
    assert item.quantity == 8

    assert {:error, :not_found} = CartServer.update_quantity(pid, "ghost", 3)
    assert {:error, :invalid_quantity} = CartServer.update_quantity(pid, "a", -1)

    :ok = CartServer.update_quantity(pid, "a", 0)
    assert CartServer.totals(pid).items == []

    :ok = CartServer.add_item(pid, "b", 1, 1.0)
    :ok = CartServer.remove_item(pid, "b")
    assert CartServer.totals(pid).items == []
    assert CartServer.remove_item(pid, "missing") == :ok
  end