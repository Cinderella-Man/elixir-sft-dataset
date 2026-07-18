  test "add_item rejects non-integer and negative quantities" do
    cart = Cart.new(tax_rate: 0.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", 1.5, 10.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", -3, 10.0)
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "p", :two, 10.0)
  end