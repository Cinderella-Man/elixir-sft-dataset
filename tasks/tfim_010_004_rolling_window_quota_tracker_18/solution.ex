  test "record at exact quota boundary succeeds", %{tracker: t} do
    assert {:ok, 0} = QuotaTracker.record(t, :api, 10, 10, 1_000)
  end