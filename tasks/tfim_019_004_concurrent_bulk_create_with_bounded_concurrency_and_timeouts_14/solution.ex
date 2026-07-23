  test "peak is zero on a fresh store and after a batch with no items" do
    # No item task has ever run, so the high-water mark of simultaneously
    # running item tasks is zero — both before any call and after an empty batch.
    assert ConcurrentCatalog.peak() == 0

    assert ConcurrentCatalog.bulk_create([]) == []

    assert ConcurrentCatalog.peak() == 0
    assert ConcurrentCatalog.count() == 0
  end