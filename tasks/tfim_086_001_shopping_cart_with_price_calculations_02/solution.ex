  test "new/0 creates an empty cart with default tax rate" do
    cart = Cart.new()
    assert cart.tax_rate == 0.0
    assert cart.items == %{}
  end