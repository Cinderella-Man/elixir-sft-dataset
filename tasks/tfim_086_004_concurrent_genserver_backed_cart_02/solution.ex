  test "start_link defaults tax rate to zero" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 2, 10.0)
    totals = CartServer.totals(pid)
    assert_in_delta totals.tax, 0.0, 0.001
    assert_in_delta totals.grand_total, 20.0, 0.001
  end