  test "add_item rejects non-integer quantities" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 2.5, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 1.0, 5.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", "3", 5.0)
    assert Cart.calculate_totals(cart).items == []
  end