  test "10 items: 10% discount applied" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    totals = Cart.calculate_totals(cart)
    [item] = totals.items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end