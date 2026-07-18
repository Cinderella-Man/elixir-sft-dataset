  test "sweep does not break subsequent put/get operations", %{cache: cache} do
    TTLCache.put(cache, "k", "old", 100)
    Clock.advance(200)

    send(cache, :sweep)
    sync(cache)

    TTLCache.put(cache, "k", "new", 1_000)
    assert {:ok, "new"} = TTLCache.get(cache, "k")
  end