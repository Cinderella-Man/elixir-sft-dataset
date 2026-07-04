  test "a negatively cached key can recover to a success" do
    cl = start_cache(negative_hits: 1)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # single cached serve, exhausts the budget
    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    # backend recovers
    Tracker.set({:ok, :recovered})
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    # success is now cached permanently
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end