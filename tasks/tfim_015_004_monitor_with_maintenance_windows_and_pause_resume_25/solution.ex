  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = ManagedMonitor.deregister(mon, "nonexistent")
  end