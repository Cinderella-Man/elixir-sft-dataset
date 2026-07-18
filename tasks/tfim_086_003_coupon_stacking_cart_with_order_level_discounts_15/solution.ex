  test "repeated add_item calls sum quantities and can cross the bulk threshold" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "p", 4, 10.0)
    {:ok, cart} = Cart.add_item(cart, "p", 6, 10.0)

    [item] = Cart.calculate_totals(cart).items
    assert item.quantity == 10
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001
  end