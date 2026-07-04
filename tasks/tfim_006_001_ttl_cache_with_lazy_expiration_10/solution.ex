  test "delete removes an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 1_000)
    assert :ok = TTLCache.delete(cache, "k")
    assert :miss = TTLCache.get(cache, "k")
  end