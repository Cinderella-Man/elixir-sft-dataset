  test "invalidate_all on one table does not affect another", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate_all(cl, :users)

    # posts cache untouched
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # users cache cleared
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end