  test "interleaved puts, gets, and deletes across keys", %{cache: cache} do
    TTLCache.put(cache, "x", 1, 500)
    TTLCache.put(cache, "y", 2, 1_000)

    Clock.advance(300)
    TTLCache.put(cache, "z", 3, 400)

    assert {:ok, 1} = TTLCache.get(cache, "x")
    assert {:ok, 2} = TTLCache.get(cache, "y")
    assert {:ok, 3} = TTLCache.get(cache, "z")

    # time = 600
    Clock.advance(300)

    # expired at 500
    assert :miss = TTLCache.get(cache, "x")
    # expires at 1000
    assert {:ok, 2} = TTLCache.get(cache, "y")
    # expires at 700
    assert {:ok, 3} = TTLCache.get(cache, "z")

    TTLCache.delete(cache, "y")
    assert :miss = TTLCache.get(cache, "y")
    assert {:ok, 3} = TTLCache.get(cache, "z")

    # time = 800
    Clock.advance(200)
    # expired at 700
    assert :miss = TTLCache.get(cache, "z")
  end