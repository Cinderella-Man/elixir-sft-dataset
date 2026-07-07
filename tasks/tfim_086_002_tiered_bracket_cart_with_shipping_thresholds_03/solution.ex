  test "add_item accumulates and rejects bad quantities" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 2, 5.0)
    {:ok, cart} = Cart.add_item(cart, "p", 3, 5.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 5
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 0, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", -1, 5.0)
  end