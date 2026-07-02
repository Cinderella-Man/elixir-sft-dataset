  test "add_item adds a new product" do
    cart = Cart.new()
    {:ok, cart} = Cart.add_item(cart, "prod:1", 2, 5.0)
    totals = Cart.calculate_totals(cart)
    assert length(totals.items) == 1
    [item] = totals.items
    assert item.product_id == "prod:1"
    assert item.quantity == 2
    assert item.unit_price == 5.0
  end