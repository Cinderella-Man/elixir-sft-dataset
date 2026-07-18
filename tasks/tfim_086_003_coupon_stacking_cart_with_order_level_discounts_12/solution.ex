  test "min_subtotal is compared against the subtotal after per-item bulk discounts" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "bulk", 10, 10.0)
    # raw 10 x 10.0 = 100.0, but the bulk discount drops the subtotal to 90.0
    assert_in_delta Cart.calculate_totals(cart).subtotal, 90.0, 0.001

    assert {:error, :below_minimum} =
             Cart.apply_coupon(cart, %{
               code: "MIN100",
               type: :fixed,
               value: 5.0,
               min_subtotal: 100.0
             })
  end