  test "get returns :miss for a key that was never set", %{cache: cache} do
    assert :miss = TTLCache.get(cache, "nonexistent")
  end