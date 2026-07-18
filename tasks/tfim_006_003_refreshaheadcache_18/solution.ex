  test "re-put overwrites ttl and loader for an existing key", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> :old_refresh end)
    :ok = RefreshAheadCache.put(c, :a, :v2, 2_000, fn -> :new_refresh end)

    # The new ttl (2000) means the entry is still alive at t=1600, where the old
    # ttl (1000) would already be hard-expired.  This get also crosses the new
    # threshold (0.8 * 2000 = 1600), scheduling a refresh via the NEW loader.
    Clock.advance(1_600)
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert {:ok, :new_refresh} = RefreshAheadCache.get(c, :a)
  end