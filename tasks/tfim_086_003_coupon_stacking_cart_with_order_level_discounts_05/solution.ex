  test "order of coupons matters" do
    a = with_items(0.0)
    {:ok, a} = Cart.apply_coupon(a, %{code: "FLAT", type: :fixed, value: 20.0})
    {:ok, a} = Cart.apply_coupon(a, %{code: "PCT", type: :percentage, value: 0.10})
    # 100 -> -20 -> 80 -> -8 (10% of 80) -> 72
    assert_in_delta Cart.calculate_totals(a).discounted_subtotal, 72.0, 0.001

    b = with_items(0.0)
    {:ok, b} = Cart.apply_coupon(b, %{code: "PCT", type: :percentage, value: 0.10})
    {:ok, b} = Cart.apply_coupon(b, %{code: "FLAT", type: :fixed, value: 20.0})
    # 100 -> -10 -> 90 -> -20 -> 70
    assert_in_delta Cart.calculate_totals(b).discounted_subtotal, 70.0, 0.001
  end