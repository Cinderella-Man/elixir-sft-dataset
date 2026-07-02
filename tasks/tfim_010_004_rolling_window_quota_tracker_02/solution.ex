  test "record returns remaining quota", %{tracker: t} do
    assert {:ok, 7} = QuotaTracker.record(t, :api, 3, 10, 1_000)
  end