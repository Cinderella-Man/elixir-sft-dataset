  test "empty cart charges no shipping and zero totals" do
    cart = Cart.new(tax_rate: 0.08, shipping_flat: 9.99, free_shipping_threshold: 100.0)
    totals = Cart.calculate_totals(cart)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.shipping, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001
  end