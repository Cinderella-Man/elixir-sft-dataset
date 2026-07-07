  test "fixed coupon never pushes running amount below zero" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 50.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "BIG", type: :fixed, value: 80.0})
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.discount, 50.0, 0.001
    assert_in_delta totals.discounted_subtotal, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end