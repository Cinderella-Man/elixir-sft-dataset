  test "different window sizes on same key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 100, 2_000)

    Clock.advance(1_500)
    {:ok, _} = QuotaTracker.record(t, :api, 3, 100, 2_000)

    # With a 1000ms window, only the second record (at t=1500) is visible
    assert {:ok, 3} = QuotaTracker.usage(t, :api, 1_000)

    # With a 2000ms window, both records are visible
    assert {:ok, 8} = QuotaTracker.usage(t, :api, 2_000)
  end