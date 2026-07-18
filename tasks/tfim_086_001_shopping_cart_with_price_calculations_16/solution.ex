  test "discount threshold is per line item, not per cart" do
    cart = Cart.new()
    # discounted
    {:ok, cart} = Cart.add_item(cart, "prod:1", 10, 10.0)
    # not discounted
    {:ok, cart} = Cart.add_item(cart, "prod:2", 3, 20.0)
    totals = Cart.calculate_totals(cart)

    discounted = Enum.find(totals.items, &(&1.product_id == "prod:1"))
    full_price = Enum.find(totals.items, &(&1.product_id == "prod:2"))

    assert discounted.discount_rate == 0.1
    assert full_price.discount_rate == 0.0
    assert_in_delta discounted.line_total, 90.0, 0.001
    assert_in_delta full_price.line_total, 60.0, 0.001
  end