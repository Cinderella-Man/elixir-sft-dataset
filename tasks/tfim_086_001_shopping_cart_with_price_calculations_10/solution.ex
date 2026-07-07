  test "update_quantity changes the quantity of an item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 8)
    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 8
  end