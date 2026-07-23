  test "qty of zero is accepted and non-integer qty is rejected" do
    assert {:ok, [{0, :inserted, rec}]} =
             Inventory.bulk_upsert([
               %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 0}
             ])

    assert rec.qty == 0

    assert {:ok, [{0, :error, errs}]} =
             Inventory.bulk_upsert(
               [%{"sku" => "B", "name" => "Beta", "price" => 10, "qty" => "3"}],
               partial: true
             )

    assert Map.has_key?(errs, "qty")
    assert Inventory.get("B") == nil
    assert Inventory.count() == 1
  end