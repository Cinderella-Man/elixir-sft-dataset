  test "update_quantity rejects negative quantity" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    assert {:error, :invalid_quantity} = Cart.update_quantity(cart, "prod:1", -3)
  end