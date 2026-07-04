  test "invalidate only removes the targeted key, leaving others intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    CacheLayer.invalidate(cl, :users, "u:1")

    # u:2 still cached — no extra fallback call
    CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2

    # u:1 was evicted — fallback fires again
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 3
  end