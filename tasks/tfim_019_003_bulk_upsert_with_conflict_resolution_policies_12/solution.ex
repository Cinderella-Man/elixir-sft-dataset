  test "empty batch succeeds" do
    assert {:ok, []} = Inventory.bulk_upsert([])
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end