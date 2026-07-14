  test "accumulated item keeps the product_id and unit_price it was added with" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, :sku_42, 2, 3.0)
    :ok = CartServer.add_item(pid, :sku_42, 5, 3.0)

    [item] = CartServer.totals(pid).items
    assert item.product_id == :sku_42
    assert item.quantity == 7
    assert_in_delta item.unit_price, 3.0, 0.001
    assert item.discount_rate == 0.0
    assert_in_delta item.line_total, 21.0, 0.001
  end