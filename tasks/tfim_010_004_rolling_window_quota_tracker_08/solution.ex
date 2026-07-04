  test "usage returns total for known key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 3, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    assert {:ok, 8} = QuotaTracker.usage(t, :api, 1_000)
  end