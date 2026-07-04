  test "put resets the TTL for an existing key", %{cache: cache} do
    TTLCache.put(cache, "k", "v1", 500)
    Clock.advance(400)

    # Overwrite with a fresh TTL of 500 — new expiry is at time 900
    TTLCache.put(cache, "k", "v2", 500)

    # now at time 600 — would have expired under old TTL
    Clock.advance(200)
    assert {:ok, "v2"} = TTLCache.get(cache, "k")

    # now at time 1000 — past new expiry of 900
    Clock.advance(400)
    assert :miss = TTLCache.get(cache, "k")
  end