  test "all/0 returns every stored record" do
    assert Inventory.all() == []

    seed("A", "Alpha", 10, 2)
    seed("B", "Beta", 20, 0)

    records = Inventory.all()
    assert length(records) == 2

    by_sku = Map.new(records, fn r -> {r.sku, r} end)
    assert Map.keys(by_sku) |> Enum.sort() == ["A", "B"]
    assert by_sku["A"].name == "Alpha"
    assert by_sku["A"].price == 10
    assert by_sku["A"].qty == 2
    assert by_sku["B"].name == "Beta"
    assert by_sku["B"].qty == 0
  end