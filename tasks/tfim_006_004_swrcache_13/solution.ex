  test "sweep removes entries past stale window, keeps stale-but-live entries", %{c: c} do
    # Reset Clock to 0 (setup already started it)
    Clock.set(0)

    # hard expires at 300
    :ok = SwrCache.put(c, :a, 1, 100, 200, fn -> :_ end)
    # hard expires at 3000
    :ok = SwrCache.put(c, :b, 2, 200, 2_800, fn -> :_ end)

    Clock.advance(500)
    send(c, :sweep)

    # Only the past-stale entry :a is dropped; the stale-but-live :b survives.
    assert %{entries: 1} = SwrCache.stats(c)

    assert :miss = SwrCache.get(c, :a)
    # :b is stale now (t=500, fresh_until=200) but NOT past hard expiry (3000)
    assert {:ok, 2, :stale} = SwrCache.get(c, :b)
  end