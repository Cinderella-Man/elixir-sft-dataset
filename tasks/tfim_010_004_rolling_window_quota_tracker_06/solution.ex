  test "remaining returns full quota for unknown key", %{tracker: t} do
    assert {:ok, 100} = QuotaTracker.remaining(t, :unknown, 100, 1_000)
  end