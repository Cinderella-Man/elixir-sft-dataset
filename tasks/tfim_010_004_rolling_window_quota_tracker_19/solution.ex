  test "record of 1 over quota fails", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    assert {:error, :quota_exceeded, 1} = QuotaTracker.record(t, :api, 1, 10, 1_000)
  end