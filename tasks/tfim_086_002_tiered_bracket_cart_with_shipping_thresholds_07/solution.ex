  test "tax is charged on the discounted subtotal, not on shipping" do
    cart = Cart.new(tax_rate: 0.1, shipping_flat: 5.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 100.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.tax, 10.0, 0.001
    assert_in_delta totals.shipping, 5.0, 0.001
    assert_in_delta totals.grand_total, 115.0, 0.001
  end