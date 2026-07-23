  test "omitting on_conflict overwrites an existing sku with the incoming record" do
    seed("A", "Old", 10, 5)

    attrs = %{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}
    assert {:ok, [{0, :updated, rec}]} = Inventory.bulk_upsert([attrs])

    assert rec.name == "New"
    assert rec.price == 20
    assert rec.qty == 3
    assert Inventory.get("A").name == "New"
    assert Inventory.get("A").price == 20
    assert Inventory.get("A").qty == 3
    assert Inventory.count() == 1
  end