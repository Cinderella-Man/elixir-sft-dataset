  test "add_item rejects non-integer quantities and leaves the cart untouched" do
    {:ok, pid} = CartServer.start_link()

    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 2.0, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", 1.5, 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", "3", 5.0)
    assert {:error, :invalid_quantity} = CartServer.add_item(pid, "a", :two, 5.0)

    assert CartServer.totals(pid).items == []
  end