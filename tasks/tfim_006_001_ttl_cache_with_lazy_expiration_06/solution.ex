  test "get returns :miss after TTL has elapsed", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    assert {:ok, "v"} = TTLCache.get(cache, "k")

    Clock.advance(501)
    assert :miss = TTLCache.get(cache, "k")
  end