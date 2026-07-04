  test "entries within window are kept, expired entries are dropped", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 3, 10, 1_000)

    Clock.advance(500)
    {:ok, _} = QuotaTracker.record(t, :api, 4, 10, 1_000)

    # At 1001ms: first record (at t=0) expires, second (at t=500) still live
    Clock.advance(501)

    assert {:ok, 4} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 6} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end