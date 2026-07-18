  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = AsyncMonitor.deregister(mon, "nonexistent")
  end