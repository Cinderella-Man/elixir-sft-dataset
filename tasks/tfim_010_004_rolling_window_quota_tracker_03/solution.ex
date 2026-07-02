  test "multiple records accumulate usage", %{tracker: t} do
    assert {:ok, 7} = QuotaTracker.record(t, :api, 3, 10, 1_000)
    assert {:ok, 2} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end