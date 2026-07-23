  test "name outside the 1-100 character range is a validation error" do
    long = String.duplicate("n", 101)

    assert {:error, [{0, :error, long_errs}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => long, "price" => 10}])

    assert Map.has_key?(long_errs, "name")
    assert is_list(long_errs["name"])
    assert Enum.all?(long_errs["name"], &is_binary/1)
    assert Inventory.count() == 0

    assert {:error, [{0, :error, blank_errs}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "", "price" => 10}])

    assert Map.has_key?(blank_errs, "name")
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end