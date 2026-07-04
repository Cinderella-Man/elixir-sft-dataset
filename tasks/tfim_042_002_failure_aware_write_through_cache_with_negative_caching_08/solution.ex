  test "invalidate removes a cached success" do
    cl = start_cache([])
    Tracker.set({:ok, :v})

    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
    :ok = CacheLayer.invalidate(cl, :users, "u:1")
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end