  test "refresh resets TTL to now + original ttl_ms", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    Clock.advance(850)
    RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    # The refresh applied at t=850 should set expires_at = 850 + 1000 = 1850.
    # At t=1600 (age=750 < threshold 800) we're still fresh and no new refresh fires.
    Clock.advance(750)
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)

    # At t=1900 we're past the NEW expiry.
    Clock.advance(300)
    assert :miss = RefreshAheadCache.get(c, :a)
  end