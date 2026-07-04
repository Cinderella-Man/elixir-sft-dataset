  test "invalidate_all clears successes and failures for a table" do
    cl = start_cache(negative_hits: 5)

    Tracker.set({:ok, :v})
    CacheLayer.fetch(cl, :users, "ok", &Tracker.fallback/0)
    Tracker.set({:error, :db_down})
    CacheLayer.fetch(cl, :users, "bad", &Tracker.fallback/0)
    assert Tracker.count() == 2

    :ok = CacheLayer.invalidate_all(cl, :users)

    Tracker.set({:ok, :again})
    assert {:ok, :again} = CacheLayer.fetch(cl, :users, "ok", &Tracker.fallback/0)
    assert {:ok, :again} = CacheLayer.fetch(cl, :users, "bad", &Tracker.fallback/0)
    assert Tracker.count() == 4
  end