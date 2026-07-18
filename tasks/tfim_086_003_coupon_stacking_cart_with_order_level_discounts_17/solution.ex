  test "update_quantity rejects a negative quantity and leaves the cart usable" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 2, 10.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "p", -1)

    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 20.0, 0.001
    # :tax_rate defaults to 0.0, so no tax is added
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 20.0, 0.001
  end