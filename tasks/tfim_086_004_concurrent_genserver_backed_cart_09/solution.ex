  test "every item map exposes all five documented keys" do
    {:ok, pid} = CartServer.start_link()
    :ok = CartServer.add_item(pid, "a", 3, 4.0)

    [item] = CartServer.totals(pid).items

    for key <- [:product_id, :quantity, :unit_price, :discount_rate, :line_total] do
      assert Map.has_key?(item, key), "item map is missing #{inspect(key)}"
    end
  end