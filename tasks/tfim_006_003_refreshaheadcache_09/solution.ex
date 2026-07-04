  test "rapid gets past threshold only trigger ONE refresh", %{c: c} do
    start_supervised!({Loader, [:v2]})

    # Use a slow loader to ensure the first refresh is still in flight while
    # we fire the follow-up gets.
    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # 10 rapid reads
    for _ <- 1..10, do: assert({:ok, :v1} = RefreshAheadCache.get(c, :a))

    # Should see exactly 1 refresh in flight
    %{refreshes_in_flight: n} = RefreshAheadCache.stats(c)
    assert n == 1

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end