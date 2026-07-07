  test "stacking applies coupons in order" do
    cart = with_items(0.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "PCT", type: :percentage, value: 0.10})
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "FLAT", type: :fixed, value: 20.0})
    totals = Cart.calculate_totals(cart)
    # 100 -> -10 (10%) -> 90 -> -20 (fixed) -> 70
    assert_in_delta totals.discount, 30.0, 0.001
    assert_in_delta totals.discounted_subtotal, 70.0, 0.001
    assert totals.coupons == ["PCT", "FLAT"]
  end