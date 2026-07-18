  test "sweep removes hard-expired entries", %{c: c} do
    Clock.set(0)

    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> 99 end)
    :ok = RefreshAheadCache.put(c, :b, 2, 5_000, fn -> 99 end)

    Clock.advance(2_000)
    send(c, :sweep)

    # A synchronous call cannot be served until the sweep message ahead of it
    # in the mailbox has been processed, so the sweep is done once this returns.
    assert %{entries: 1} = RefreshAheadCache.stats(c)

    assert :miss = RefreshAheadCache.get(c, :a)
    assert {:ok, 2} = RefreshAheadCache.get(c, :b)
  end