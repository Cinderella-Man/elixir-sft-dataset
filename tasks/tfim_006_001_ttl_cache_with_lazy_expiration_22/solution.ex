  test "put with a shorter TTL retires the previous later expiration", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 1_000)
    Clock.advance(100)

    # New expiry is 100 + 50 = 150, well before the old expiry of 1_100.
    TTLCache.put(cache, "k", "v2", 50)

    Clock.advance(100)

    # time = 200: past the new expiry (150) even though the old expiry is far away.
    assert :miss = TTLCache.get(cache, "k")
  end