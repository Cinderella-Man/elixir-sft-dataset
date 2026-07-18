  test "default refresh_threshold triggers at age == 0.8 * ttl", %{c: _c} do
    start_supervised!({Loader, [:v2]})

    {:ok, d} =
      RefreshAheadCache.start_link(clock: &Clock.now/0, sweep_interval_ms: :infinity)

    :ok = RefreshAheadCache.put(d, :a, :v1, 1_000, &Loader.next_value/0)

    # Default threshold 0.8 => boundary at age 800.  At 799 no refresh fires.
    Clock.advance(799)
    assert {:ok, :v1} = RefreshAheadCache.get(d, :a)
    :ok = wait_for_idle(d)
    assert Loader.calls() == 0

    # At age exactly 800 the default threshold fires the refresh.
    Clock.advance(1)
    assert {:ok, :v1} = RefreshAheadCache.get(d, :a)
    :ok = wait_for_idle(d)
    assert Loader.calls() == 1
  end