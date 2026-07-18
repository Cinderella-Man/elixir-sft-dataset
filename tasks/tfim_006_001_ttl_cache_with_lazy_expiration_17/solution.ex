  test "sweep removes all expired entries from internal state", %{cache: cache} do
    for i <- 1..100 do
      TTLCache.put(cache, "key:#{i}", i, 100)
    end

    Clock.advance(200)

    # Trigger sweep manually, then wait for the cache to finish handling it
    send(cache, :sweep)
    sync(cache)

    # Rewind the clock to a moment when every entry was still live. Entries the
    # sweep dropped stay gone; entries it left behind would read as hits again.
    Clock.set(0)

    for i <- 1..100 do
      assert :miss = TTLCache.get(cache, "key:#{i}")
    end
  end