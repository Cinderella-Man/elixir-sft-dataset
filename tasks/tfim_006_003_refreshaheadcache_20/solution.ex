  test "the same loader is reused across successive refreshes", %{c: c} do
    start_supervised!({Loader, [:r1, :r2]})
    :ok = RefreshAheadCache.put(c, :a, :v0, 1_000, &Loader.next_value/0)

    # First refresh at t=850 -> :r1, TTL reset to expires_at = 1850.
    Clock.advance(850)
    assert {:ok, :v0} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert {:ok, :r1} = RefreshAheadCache.get(c, :a)

    # Second crossing on the refreshed entry must call the loader AGAIN -> :r2.
    Clock.advance(810)
    assert {:ok, :r1} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)
    assert {:ok, :r2} = RefreshAheadCache.get(c, :a)

    assert Loader.calls() == 2
  end