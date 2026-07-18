  test "reset clears all usage for a key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    assert :ok = QuotaTracker.reset(t, :api)
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 10} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end