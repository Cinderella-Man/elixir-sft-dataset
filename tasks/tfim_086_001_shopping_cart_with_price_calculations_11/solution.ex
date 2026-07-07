  test "update_quantity to 0 removes the item" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 0)
    assert Cart.calculate_totals(cart).items == []
  end