  test "reset returns :ok for unknown key", %{tracker: t} do
    assert :ok = QuotaTracker.reset(t, :nonexistent)
  end