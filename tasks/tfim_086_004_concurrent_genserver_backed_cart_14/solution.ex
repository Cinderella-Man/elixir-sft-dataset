  test "accumulated adds crossing the bulk threshold earn the discount" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 6, 10.0)

    [before] = CartServer.totals(pid).items
    assert before.discount_rate == 0.0
    assert_in_delta before.line_total, 60.0, 0.001

    :ok = CartServer.add_item(pid, "a", 4, 10.0)

    [after_bulk] = CartServer.totals(pid).items
    assert after_bulk.quantity == 10
    assert after_bulk.discount_rate == 0.1
    assert_in_delta after_bulk.line_total, 90.0, 0.001
  end