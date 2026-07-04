  test "usage returns 0 for unknown key", %{tracker: t} do
    assert {:ok, 0} = QuotaTracker.usage(t, :unknown, 1_000)
  end