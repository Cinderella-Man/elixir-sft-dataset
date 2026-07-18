  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = RateMonitor.deregister(mon, "nonexistent")
  end