  test "in-batch duplicate sku with merge accumulates across entries" do
    items = [
      %{"sku" => "A", "name" => "First", "price" => 1, "qty" => 2},
      %{"sku" => "A", "name" => "Second", "price" => 2, "qty" => 3}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items, on_conflict: :merge)
    assert {0, :inserted, first} = Enum.at(results, 0)
    assert {1, :updated, second} = Enum.at(results, 1)
    assert first.qty == 2
    assert second.qty == 5
    assert Inventory.get("A").qty == 5
    assert Inventory.count() == 1
  end