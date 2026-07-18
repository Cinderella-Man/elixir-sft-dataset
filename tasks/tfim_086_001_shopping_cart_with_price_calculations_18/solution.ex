  test "zero tax rate produces no tax" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 50.0)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, totals.subtotal, 0.001
  end