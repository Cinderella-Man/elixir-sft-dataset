  test "add_item rejects negative quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", -1, 5.0)
  end