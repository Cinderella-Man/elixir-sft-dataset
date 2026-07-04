  test "skip policy leaves the existing record untouched" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :skipped, existing}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "X", "price" => 99, "qty" => 9}],
               on_conflict: :skip
             )

    assert existing.name == "Old"
    assert existing.qty == 5
    assert Inventory.get("A").qty == 5
  end