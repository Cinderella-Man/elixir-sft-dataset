  test "keys track usage independently", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 5, 1_000)

    assert {:ok, 8} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(t, :uploads, 1_000)
    assert {:ok, 2} = QuotaTracker.remaining(t, :api, 10, 1_000)
    assert {:ok, 2} = QuotaTracker.remaining(t, :uploads, 5, 1_000)
  end