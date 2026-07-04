  test "nil is a valid cached success value" do
    cl = start_cache([])
    Tracker.set({:ok, nil})

    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", &Tracker.fallback/0)
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end