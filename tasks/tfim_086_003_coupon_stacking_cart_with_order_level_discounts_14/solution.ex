  test "remove_item drops the product entirely and is a no-op for an absent product" do
    cart = Cart.new(tax_rate: 0.0)
    {:ok, cart} = Cart.add_item(cart, "a", 2, 10.0)
    {:ok, cart} = Cart.add_item(cart, "b", 3, 5.0)

    removed = Cart.remove_item(cart, "a")
    ids = Enum.map(Cart.calculate_totals(removed).items, & &1.product_id)
    assert ids == ["b"]
    assert_in_delta Cart.calculate_totals(removed).subtotal, 15.0, 0.001

    same = Cart.remove_item(removed, "ghost")
    assert Cart.calculate_totals(same) == Cart.calculate_totals(removed)
  end