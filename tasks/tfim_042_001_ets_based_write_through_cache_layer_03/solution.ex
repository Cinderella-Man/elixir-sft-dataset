  test "cache hit does not call fallback a second time", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end