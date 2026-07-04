  test "get past refresh threshold triggers loader; subsequent gets see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # Past threshold (0.8 * 1000 = 800ms).
    Clock.advance(850)

    # This get returns the OLD value and schedules a refresh.
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # Next get should see the refreshed value.
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)
  end