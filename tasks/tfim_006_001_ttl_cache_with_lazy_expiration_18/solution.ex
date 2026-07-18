  test "sweep preserves entries that have not yet expired", %{cache: cache} do
    TTLCache.put(cache, "short", "gone", 100)
    TTLCache.put(cache, "long", "stays", 5_000)

    Clock.advance(200)

    send(cache, :sweep)
    sync(cache)

    assert :miss = TTLCache.get(cache, "short")
    assert {:ok, "stays"} = TTLCache.get(cache, "long")

    # Back at a time when both entries were live: only "long" survived the sweep,
    # so only "long" can still be read.
    Clock.set(0)
    assert :miss = TTLCache.get(cache, "short")
    assert {:ok, "stays"} = TTLCache.get(cache, "long")
  end