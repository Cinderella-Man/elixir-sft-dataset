  test "replace policy overwrites the existing record" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :replace
             )

    assert rec.name == "New"
    assert rec.price == 20
    assert rec.qty == 3
    assert Inventory.get("A").qty == 3
    assert Inventory.count() == 1
  end