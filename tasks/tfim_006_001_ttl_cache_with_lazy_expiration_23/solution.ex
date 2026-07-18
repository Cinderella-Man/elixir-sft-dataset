  test "get returns :miss at exactly the TTL boundary", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    Clock.advance(500)
    assert :miss = TTLCache.get(cache, "k")
  end