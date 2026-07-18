  test "discounted line echoes the raw unit price, not the discounted price" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "prod:1"
    assert item.quantity == 10
    assert item.unit_price == 10.0
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
  end