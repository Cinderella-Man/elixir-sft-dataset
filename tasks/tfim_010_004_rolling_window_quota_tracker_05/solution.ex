  test "rejected record does not consume quota", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)
    {:error, :quota_exceeded, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    # Only the first 8 should be recorded
    assert {:ok, 2} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end