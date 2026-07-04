  test "merge policy accumulates qty" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :merge
             )

    assert rec.qty == 8
    assert rec.name == "New"
    assert Inventory.get("A").qty == 8
  end