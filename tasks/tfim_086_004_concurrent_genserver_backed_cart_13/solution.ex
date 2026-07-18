  test "subtotal sums discounted and undiscounted lines together with tax on top" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.05)
    :ok = CartServer.add_item(pid, "bulk", 10, 10.0)
    :ok = CartServer.add_item(pid, "single", 2, 5.0)

    totals = CartServer.totals(pid)
    by_id = Map.new(totals.items, fn item -> {item.product_id, item} end)

    assert by_id["bulk"].discount_rate == 0.1
    assert_in_delta by_id["bulk"].line_total, 90.0, 0.001
    assert by_id["single"].discount_rate == 0.0
    assert_in_delta by_id["single"].line_total, 10.0, 0.001

    assert_in_delta totals.subtotal, 100.0, 0.001
    assert_in_delta totals.tax, 5.0, 0.001
    assert_in_delta totals.grand_total, 105.0, 0.001
  end