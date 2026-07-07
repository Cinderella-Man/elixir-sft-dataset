  test "add_item accumulates quantity for existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 3, 5.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 4, 5.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.quantity == 7
  end