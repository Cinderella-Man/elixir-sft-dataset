  test "base lifecycle still works with per-item bulk discount" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "p", 10, 10.0)
    [item] = Cart.calculate_totals(cart).items
    assert item.discount_rate == 0.1
    assert_in_delta item.line_total, 90.0, 0.001

    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 0, 10.0)
    assert {:error, :not_found} = Cart.update_quantity(cart, "ghost", 3)
    {:ok, cart} = Cart.update_quantity(cart, "p", 0)
    assert Cart.calculate_totals(cart).items == []
  end