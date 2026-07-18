  test "shipping is waived when the discounted subtotal exactly equals the threshold" do
    cart = Cart.new(shipping_flat: 6.5, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 4, 25.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
    assert_in_delta totals.grand_total, 100.0, 0.001
  end