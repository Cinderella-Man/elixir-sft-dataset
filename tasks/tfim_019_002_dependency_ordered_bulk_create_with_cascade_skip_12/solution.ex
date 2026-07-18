  test "empty batch succeeds and stores nothing" do
    assert {:ok, []} = Catalog.bulk_create([])
    assert Catalog.count() == 0
    assert Catalog.all() == []
  end