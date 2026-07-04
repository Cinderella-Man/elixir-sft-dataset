  test "get returns hit just before TTL expires", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 500)
    Clock.advance(499)
    assert {:ok, "v"} = TTLCache.get(cache, "k")
  end