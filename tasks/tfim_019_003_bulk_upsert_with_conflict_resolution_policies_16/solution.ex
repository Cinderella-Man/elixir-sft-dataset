  test "name of exactly 100 characters is accepted" do
    name = String.duplicate("n", 100)

    assert {:ok, [{0, :inserted, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => name, "price" => 10}])

    assert rec.name == name
    assert Inventory.count() == 1
    assert Inventory.get("A").name == name
  end