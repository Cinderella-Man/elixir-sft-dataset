  test "each totals item map carries the unit_price and every documented key" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "a", 3, 12.5)
    {:ok, cart} = Cart.add_item(cart, "a", 7, 12.5)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "a"
    assert item.quantity == 10
    assert item.unit_price == 12.5
    assert item.discount_rate == 0.05
    assert_in_delta item.line_total, 118.75, 0.001

    assert Map.keys(item) |> Enum.sort() ==
             [:discount_rate, :line_total, :product_id, :quantity, :unit_price]
  end