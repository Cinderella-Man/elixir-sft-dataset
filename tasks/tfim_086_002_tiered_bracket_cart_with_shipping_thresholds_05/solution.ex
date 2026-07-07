  test "bracket tiers pick the highest applicable rate" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "a", 9, 10.0)
    {:ok, cart} = Cart.add_item(cart, "b", 10, 10.0)
    {:ok, cart} = Cart.add_item(cart, "c", 25, 10.0)
    {:ok, cart} = Cart.add_item(cart, "d", 50, 10.0)
    items = Cart.calculate_totals(cart).items

    a = Enum.find(items, &(&1.product_id == "a"))
    b = Enum.find(items, &(&1.product_id == "b"))
    c = Enum.find(items, &(&1.product_id == "c"))
    d = Enum.find(items, &(&1.product_id == "d"))

    assert a.discount_rate == 0.0
    assert b.discount_rate == 0.05
    assert c.discount_rate == 0.10
    assert d.discount_rate == 0.15

    assert_in_delta a.line_total, 90.0, 0.001
    assert_in_delta b.line_total, 95.0, 0.001
    assert_in_delta c.line_total, 225.0, 0.001
    assert_in_delta d.line_total, 425.0, 0.001
  end