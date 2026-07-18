  test "update_quantity back below the threshold drops the discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 11, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 99.0, 0.001

    {:ok, cart} = Cart.update_quantity(cart, "prod:1", 9)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 90.0, 0.001
  end