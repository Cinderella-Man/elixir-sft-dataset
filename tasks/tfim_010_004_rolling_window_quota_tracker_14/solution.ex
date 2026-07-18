  test "record works normally after reset", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    QuotaTracker.reset(t, :api)

    assert {:ok, 5} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end