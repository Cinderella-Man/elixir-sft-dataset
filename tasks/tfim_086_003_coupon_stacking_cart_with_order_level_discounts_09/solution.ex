  test "min_subtotal defaults to zero and always passes" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 1, 1.0)
    {:ok, cart} = Cart.apply_coupon(cart, %{code: "ANY", type: :fixed, value: 0.5})
    assert Cart.calculate_totals(cart).coupons == ["ANY"]
  end