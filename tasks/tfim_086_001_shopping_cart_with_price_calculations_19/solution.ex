  test "calculate_totals on empty cart returns all zeros" do
    cart = Cart.new(tax_rate: 0.08)
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end