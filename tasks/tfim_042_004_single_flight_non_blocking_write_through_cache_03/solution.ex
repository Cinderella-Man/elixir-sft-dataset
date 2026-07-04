  test "cache hit does not call the fallback again", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end