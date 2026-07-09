  test "rejects malformed coupons" do
    cart = with_items(0.0)
    assert {:error, :invalid_coupon} = Cart.apply_coupon(cart, %{type: :percentage, value: 0.1})

    assert {:error, :invalid_coupon} =
             Cart.apply_coupon(cart, %{code: "Z", type: :bogus, value: 1})

    assert {:error, :invalid_coupon} =
             Cart.apply_coupon(cart, %{code: "Z", type: :fixed, value: -1})
  end