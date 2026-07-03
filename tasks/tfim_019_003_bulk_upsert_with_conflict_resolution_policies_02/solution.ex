  test "inserts new items (all-or-nothing)" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 2},
      %{"sku" => "B", "name" => "Beta", "price" => 20}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items)
    assert {0, :inserted, a} = Enum.at(results, 0)
    assert {1, :inserted, b} = Enum.at(results, 1)
    assert a.qty == 2
    assert b.qty == 0
    assert Inventory.count() == 2
  end