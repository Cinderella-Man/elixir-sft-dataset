  test "expired key is removed from internal state on read", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 100)
    Clock.advance(200)

    # Read triggers lazy deletion
    assert :miss = TTLCache.get(cache, "k")

    # Rewinding the clock to well before the expiry cannot resurrect the value:
    # a merely-expired-but-still-stored entry would become readable again, while
    # a lazily deleted one stays a miss forever.
    Clock.set(10)
    assert :miss = TTLCache.get(cache, "k")

    # The key behaves exactly like one that was never written.
    assert :ok = TTLCache.delete(cache, "k")
    assert :miss = TTLCache.get(cache, "k")
  end