  test "successful fallback is cached permanently" do
    cl = start_cache([])
    Tracker.set({:ok, %{name: "Alice"}})

    assert {:ok, %{name: "Alice"}} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, %{name: "Alice"}} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end