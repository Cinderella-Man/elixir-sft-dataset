  test "per-item discount at threshold and tax on discounted subtotal" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.1)
    :ok = CartServer.add_item(pid, "a", 9, 10.0)
    [nine] = CartServer.totals(pid).items
    assert nine.discount_rate == 0.0
    assert_in_delta nine.line_total, 90.0, 0.001

    :ok = CartServer.update_quantity(pid, "a", 10)
    totals = CartServer.totals(pid)
    [ten] = totals.items
    assert ten.discount_rate == 0.1
    assert_in_delta ten.line_total, 90.0, 0.001
    assert_in_delta totals.subtotal, 90.0, 0.001
    assert_in_delta totals.tax, 9.0, 0.001
    assert_in_delta totals.grand_total, 99.0, 0.001
  end