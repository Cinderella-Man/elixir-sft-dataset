  test "tax is applied on top of the discounted subtotal" do
    cart = Cart.new(tax_rate: 0.1)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # line_total = 90.0, tax = 9.0, grand_total = 99.0
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
  end