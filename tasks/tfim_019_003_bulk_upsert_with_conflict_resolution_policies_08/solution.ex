  test "all-or-nothing rolls back when any item is invalid" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10},
      %{"sku" => "B", "price" => 5}
    ]

    assert {:error, results} = Inventory.bulk_upsert(items)
    assert {0, :ok, :valid} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "name")
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end