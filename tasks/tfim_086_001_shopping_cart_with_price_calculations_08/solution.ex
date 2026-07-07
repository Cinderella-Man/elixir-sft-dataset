  test "remove_item removes an existing product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart = Cart.remove_item(cart, "prod:1")
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
  end