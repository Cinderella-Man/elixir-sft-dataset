  test "coupon whose min_subtotal exactly equals the subtotal is accepted" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 100.0)

    {:ok, cart} =
      Cart.apply_coupon(cart, %{
        code: "EXACT",
        type: :percentage,
        value: 0.10,
        min_subtotal: 100.0
      })

    totals = Cart.calculate_totals(cart)
    assert totals.coupons == ["EXACT"]
    assert_in_delta totals.discount, 10.0, 0.001
  end