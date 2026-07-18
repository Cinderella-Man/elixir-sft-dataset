  test "record with amount 0 succeeds without affecting quota", %{tracker: t} do
    assert {:ok, 10} = QuotaTracker.record(t, :api, 0, 10, 1_000)
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
  end