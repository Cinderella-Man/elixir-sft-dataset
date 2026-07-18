  test "add_item rejects a non-integer quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", 2.5, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", "3", 5.0)
    assert Cart.calculate_totals(cart).items == []
  end