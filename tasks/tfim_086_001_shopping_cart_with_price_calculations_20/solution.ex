  test "full lifecycle: add, update, remove, recalculate" do
    cart = Cart.new(tax_rate: 0.05)

    # 100.0, no discount
    {:ok, cart} = Cart.add_item(cart, "a", 5, 20.0)
    # 72.0 after 10% discount
    {:ok, cart} = Cart.add_item(cart, "b", 10, 8.0)
    # 50.0, no discount
    {:ok, cart} = Cart.add_item(cart, "c", 1, 50.0)

    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 222.0, 0.001

    # Bump "a" over the discount threshold
    # now 180.0 after discount
    {:ok, cart} = Cart.update_quantity(cart, "a", 10)
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 302.0, 0.001

    # Remove "c"
    cart = Cart.remove_item(cart, "c")
    totals = Cart.calculate_totals(cart)
    assert_in_delta totals.subtotal, 252.0, 0.001
    assert_in_delta totals.tax, 252.0 * 0.05, 0.001
    assert_in_delta totals.grand_total, 252.0 * 1.05, 0.001
  end