  test "delete on an already-expired key returns :ok", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 100)
    Clock.advance(200)
    assert :ok = TTLCache.delete(cache, "k")
  end