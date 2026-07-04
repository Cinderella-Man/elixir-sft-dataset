  test "partial mode applies valid items and reports invalid ones" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10},
      %{"sku" => "B", "price" => -5}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items, partial: true)
    assert {0, :inserted, _} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "price")
    assert Inventory.count() == 1
    assert [%{sku: "A"}] = Inventory.all()
  end