  test "accumulated adds crossing the threshold earn the discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 5, 10.0)
    [before] = Cart.calculate_totals(cart).items
    assert before.discount_rate == 0.0

    {:ok, cart} = Cart.add_item(cart, "prod:1", 5, 10.0)
    totals = Cart.calculate_totals(cart)
    assert length(totals.items) == 1
    [item] = totals.items
    assert item.quantity == 10
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
  end