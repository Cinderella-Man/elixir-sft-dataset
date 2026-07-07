  test "new/0 uses defaults" do
    cart = Cart.new()
    assert cart.tax_rate == 0.0
    assert cart.shipping_flat == 0.0
    assert cart.free_shipping_threshold == nil
    assert cart.discount_tiers == [{10, 0.05}, {25, 0.10}, {50, 0.15}]
    assert cart.items == %{}
  end