  test "cache miss calls fallback and returns value", %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 1
  end