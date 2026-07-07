  test "rejects coupons below the minimum subtotal" do
    cart = with_items(0.0)
    assert {:error, :below_minimum} =
             Cart.apply_coupon(cart, %{
               code: "VIP",
               type: :percentage,
               value: 0.25,
               min_subtotal: 200.0
             })
  end