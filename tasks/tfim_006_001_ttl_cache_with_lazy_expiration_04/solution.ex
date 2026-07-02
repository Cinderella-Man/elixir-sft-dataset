  test "put overwrites an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 1_000)
    TTLCache.put(cache, "k", "v2", 1_000)
    assert {:ok, "v2"} = TTLCache.get(cache, "k")
  end