  test "very short TTL expires almost immediately", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 1)
    Clock.advance(2)
    assert :miss = TTLCache.get(cache, "k")
  end