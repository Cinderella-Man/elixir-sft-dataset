  test "with negative_hits: 0 every fetch retries the failing backend" do
    cl = start_cache(negative_hits: 0)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end