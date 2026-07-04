  test "empty batch returns an empty list" do
    assert [] = ConcurrentCatalog.bulk_create([])
    assert ConcurrentCatalog.count() == 0
    assert ConcurrentCatalog.all() == []
  end