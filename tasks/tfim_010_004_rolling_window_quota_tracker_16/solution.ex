  test "resetting one key does not affect another", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 5, 1_000)

    QuotaTracker.reset(t, :api)

    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(t, :uploads, 1_000)
  end