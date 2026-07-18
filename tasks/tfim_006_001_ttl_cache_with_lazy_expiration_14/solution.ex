  test "deleting one key does not affect another", %{cache: cache} do
    TTLCache.put(cache, "a", 1, 1_000)
    TTLCache.put(cache, "b", 2, 1_000)

    TTLCache.delete(cache, "a")

    assert :miss = TTLCache.get(cache, "a")
    assert {:ok, 2} = TTLCache.get(cache, "b")
  end