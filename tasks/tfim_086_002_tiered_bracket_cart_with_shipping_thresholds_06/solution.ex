  test "custom discount tiers override defaults" do
    cart = Cart.new(discount_tiers: [{5, 0.20}])
    {:ok, cart} = Cart.add_item(cart, "a", 5, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.20
    assert_in_delta item.line_total, 40.0, 0.001
  end