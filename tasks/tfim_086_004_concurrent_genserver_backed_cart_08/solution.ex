  test "each cart process holds independent state" do
    {:ok, a} = CartServer.start_link()
    {:ok, b} = CartServer.start_link()
    :ok = CartServer.add_item(a, "x", 5, 10.0)
    assert length(CartServer.totals(a).items) == 1
    assert CartServer.totals(b).items == []
  end