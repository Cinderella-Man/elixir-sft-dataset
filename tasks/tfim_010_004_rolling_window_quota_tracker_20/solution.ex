  test "expired entries are cleaned up by sweep", %{tracker: t} do
    for i <- 1..50 do
      {:ok, _} = QuotaTracker.record(t, "key_#{i}", 1, 100, 1_000)
    end

    Clock.advance(10_001)

    send(t, :cleanup)

    # keys/1 is a GenServer call, so it is processed after the :cleanup
    # message and also confirms the sweep did not crash the server. The sweep
    # removes keys whose usage lists are empty after eviction, and every entry
    # here is older than max_window_ms, so no keys may remain. Internal state
    # is deliberately not inspected.
    assert QuotaTracker.keys(t) == []
    assert Process.alive?(t)
  end