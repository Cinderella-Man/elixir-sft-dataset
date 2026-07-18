  test "cleanup only removes fully expired keys, keeps active ones", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :old, 5, 10, 1_000)

    Clock.advance(9_000)
    {:ok, _} = QuotaTracker.record(t, :new, 3, 10, 1_000)

    Clock.advance(1_001)

    send(t, :cleanup)

    # keys/1 is a GenServer call, so it is processed after the :cleanup
    # message and also confirms the sweep did not crash the server. :old's
    # only entry (age 10_001ms) is past max_window_ms and must be swept away;
    # :new's entry (age 1_001ms) is within max_window_ms and must survive the
    # sweep even though it is outside its own 1_000ms query window. Internal
    # state is deliberately not inspected.
    assert QuotaTracker.keys(t) == [:new]
    assert Process.alive?(t)
  end