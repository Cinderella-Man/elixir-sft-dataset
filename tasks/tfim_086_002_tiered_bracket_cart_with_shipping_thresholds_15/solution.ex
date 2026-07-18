  test "highest applicable tier wins regardless of tier list order" do
    cart = Cart.new(discount_tiers: [{50, 0.15}, {10, 0.05}, {25, 0.10}])
    {:ok, cart} = Cart.add_item(cart, "a", 60, 10.0)
    {:ok, cart} = Cart.add_item(cart, "b", 26, 10.0)
    items = Cart.calculate_totals(cart).items
    a = Enum.find(items, &(&1.product_id == "a"))
    b = Enum.find(items, &(&1.product_id == "b"))
    assert a.discount_rate == 0.15
    assert b.discount_rate == 0.10
    assert_in_delta a.line_total, 510.0, 0.001
    assert_in_delta b.line_total, 234.0, 0.001
  end