  test "usage entries expire after window", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    Clock.advance(1_001)

    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 10} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end