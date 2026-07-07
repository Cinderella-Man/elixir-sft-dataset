  test "remove_item and update_quantity" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 4, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "p", 7)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 7
    {:ok, cart} = Cart.update_quantity(cart, "p", 0)
    assert Cart.calculate_totals(cart).items == []
    assert {:error, :not_found} = Cart.update_quantity(cart, "nope", 3)

    {:ok, cart} = Cart.add_item(cart, "p", 1, 1.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "p", -2)
    cart = Cart.remove_item(cart, "p")
    assert Cart.calculate_totals(cart).items == []
    assert Cart.remove_item(cart, "ghost") == cart
  end