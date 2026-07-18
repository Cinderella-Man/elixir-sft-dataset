  test "remove_item returns a bare cart struct for both hit and miss" do
    cart = Cart.new(tax_rate: 0.08)
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)

    missed = Cart.remove_item(cart, "prod:999")
    refute match?({:ok, _}, missed)
    assert is_struct(missed, Cart)
    assert missed.tax_rate == 0.08

    hit = Cart.remove_item(cart, "prod:1")
    refute match?({:ok, _}, hit)
    assert is_struct(hit, Cart)
    assert Cart.calculate_totals(hit).items == []
  end