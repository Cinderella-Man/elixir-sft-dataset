  test "add_item rejects zero quantity" do
    cart = Cart.new()
    assert {:error, :invalid_quantity} = Cart.add_item(cart, "prod:1", 0, 5.0)
  end