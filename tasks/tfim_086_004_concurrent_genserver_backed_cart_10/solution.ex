  test "product_id and unit_price identify each line among several items" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "widget", 2, 5.0)
    :ok = CartServer.add_item(pid, "gadget", 3, 7.0)

    by_id =
      CartServer.totals(pid).items
      |> Map.new(fn item -> {item.product_id, item} end)

    assert Map.keys(by_id) |> Enum.sort() == ["gadget", "widget"]

    widget = by_id["widget"]
    assert widget.quantity == 2
    assert_in_delta widget.unit_price, 5.0, 0.001
    assert widget.discount_rate == 0.0
    assert_in_delta widget.line_total, 10.0, 0.001

    gadget = by_id["gadget"]
    assert gadget.quantity == 3
    assert_in_delta gadget.unit_price, 7.0, 0.001
    assert gadget.discount_rate == 0.0
    assert_in_delta gadget.line_total, 21.0, 0.001
  end