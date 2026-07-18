  test "update_quantity returns error for unknown product" do
    cart = Cart.new()
    assert {:error, :not_found} = Cart.update_quantity(cart, "prod:999", 5)
  end