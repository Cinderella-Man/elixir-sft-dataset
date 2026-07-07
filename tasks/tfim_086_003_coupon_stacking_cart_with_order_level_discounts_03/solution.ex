  test "percentage coupon removes a fraction of the subtotal" do
    cart = with_items(0.1)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "SAVE10", type: :percentage, value: 0.10})
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.discount, 10.0, 0.001
    assert_in_delta totals.discounted_subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
    assert totals.coupons == ["SAVE10"]
  end