  test "different tables are completely independent namespaces", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)

    # Same key, different tables — two misses
    assert CallTracker.call_count() == 2

    # Both should now be cached independently
    CacheLayer.fetch(cl, :users, "id:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end