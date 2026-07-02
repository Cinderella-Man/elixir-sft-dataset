  test "new/1 accepts a custom tax rate" do
    cart = Cart.new(tax_rate: 0.1)
    assert cart.tax_rate == 0.1
  end