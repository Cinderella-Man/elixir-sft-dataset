  test "cache miss calls the fallback and returns the value", %{cl: cl} do
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert Tracker.count() == 1
  end