  test "shipping is waived at or above the free-shipping threshold" do
    cart = Cart.new(shipping_flat: 5.0, free_shipping_threshold: 100.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 50.0)
    assert_in_delta Cart.calculate_totals(cart).shipping, 5.0, 0.001

    {:ok, cart} = Cart.update_quantity(cart, "a", 3)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 150.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
  end