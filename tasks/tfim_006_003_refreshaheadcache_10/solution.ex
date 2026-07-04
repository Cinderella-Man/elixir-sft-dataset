  test "delete during in-flight refresh discards the refresh result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # Trigger refresh
    RefreshAheadCache.get(c, :a)
    %{refreshes_in_flight: 1} = RefreshAheadCache.stats(c)

    # Delete while refresh is in flight
    RefreshAheadCache.delete(c, :a)

    # Wait for the refresh to complete — it should have been discarded
    :ok = wait_for_idle(c)
    assert :miss = RefreshAheadCache.get(c, :a)
    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end