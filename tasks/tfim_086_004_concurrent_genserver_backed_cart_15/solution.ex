  test "empty cart reports zero subtotal, tax and grand total" do
    {:ok, pid} = CartServer.start_link(tax_rate: 0.2)

    totals = CartServer.totals(pid)
    assert totals.items == []
    assert_in_delta totals.subtotal, 0.0, 0.001
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 0.0, 0.001

    :ok = CartServer.add_item(pid, "a", 1, 10.0)
    :ok = CartServer.remove_item(pid, "a")

    emptied = CartServer.totals(pid)
    assert emptied.items == []
    assert_in_delta emptied.subtotal, 0.0, 0.001
    assert_in_delta emptied.tax, 0.0, 0.001
    assert_in_delta emptied.grand_total, 0.0, 0.001
  end