  test "a nil threshold never waives shipping no matter how large the subtotal" do
    cart = Cart.new(shipping_flat: 7.5)
    {:ok, cart} = Cart.add_item(cart, "a", 100, 500.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 42_500.0, 0.001
    assert_in_delta totals.shipping, 7.5, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 42_507.5, 0.001
  end