  test "remove_item is a no-op for unknown product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    cart2 = Cart.remove_item(cart, "prod:999")
    assert Cart.calculate_totals(cart2).items == Cart.calculate_totals(cart).items
  end