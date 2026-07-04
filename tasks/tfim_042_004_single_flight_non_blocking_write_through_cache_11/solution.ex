  test "invalidate only removes the targeted key", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :users, "u:2", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.invalidate(cl, :users, "u:1")

    CacheLayer.fetch(cl, :users, "u:2", &Tracker.fallback/0)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 3
  end