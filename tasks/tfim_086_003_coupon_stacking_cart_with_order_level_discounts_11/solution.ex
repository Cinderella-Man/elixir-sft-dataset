  test "no coupons means discount is zero" do
    cart = with_items(0.1)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.discount, 0.0, 0.001
    assert_in_delta totals.discounted_subtotal, totals.subtotal, 0.001
    assert totals.coupons == []
  end