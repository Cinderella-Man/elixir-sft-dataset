  test "threshold compares against the discounted subtotal, not the undiscounted one" do
    cart = Cart.new(shipping_flat: 4.0, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 10, 10.5)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 99.75, 0.001
    assert_in_delta totals.shipping, 4.0, 0.001
  end