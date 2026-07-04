  test "invalidate removes a negatively cached entry" do
    cl = start_cache(negative_hits: 5)
    Tracker.set({:error, :db_down})

    assert {:error, :db_down} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1

    :ok = CacheLayer.invalidate(cl, :users, "u:1")

    Tracker.set({:ok, :fresh})
    assert {:ok, :fresh} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 2
  end