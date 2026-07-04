  test "a cached failure is served for exactly negative_hits reads then retried" do
    cl = start_cache(negative_hits: 2)
    Tracker.set({:error, :db_down})

    # miss -> calls fallback, caches the error
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # two cached serves, no fallback calls
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # budget exhausted -> next fetch retries
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end