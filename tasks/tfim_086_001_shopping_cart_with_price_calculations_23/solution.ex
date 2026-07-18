  test "update_quantity to 0 for an unknown product returns not_found" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    assert {:error, :not_found} = Cart.update_quantity(cart, "prod:999", 0)
    [item] = Cart.calculate_totals(cart).items
    assert item.product_id == "prod:1"
  end