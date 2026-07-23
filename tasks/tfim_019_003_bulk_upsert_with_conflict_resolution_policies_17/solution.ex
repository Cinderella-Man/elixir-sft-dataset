  test "negative qty is a validation error keyed by qty" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 1},
      %{"sku" => "B", "name" => "Beta", "price" => 20, "qty" => -1}
    ]

    assert {:error, results} = Inventory.bulk_upsert(items)
    assert {0, :ok, :valid} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "qty")
    assert is_list(errs["qty"])
    assert Enum.all?(errs["qty"], &is_binary/1)
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end