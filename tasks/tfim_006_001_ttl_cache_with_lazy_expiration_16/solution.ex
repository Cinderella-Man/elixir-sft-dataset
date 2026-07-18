  test "very large TTL works correctly", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 86_400_000)
    Clock.advance(86_399_999)
    assert {:ok, "v"} = TTLCache.get(cache, "k")

    Clock.advance(2)
    assert :miss = TTLCache.get(cache, "k")
  end