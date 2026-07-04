  test "expired usage frees quota for new records", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    {:error, :quota_exceeded, _} = QuotaTracker.record(t, :api, 1, 10, 1_000)

    Clock.advance(1_001)

    assert {:ok, 5} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end