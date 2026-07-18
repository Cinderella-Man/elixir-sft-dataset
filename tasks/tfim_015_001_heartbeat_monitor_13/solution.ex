  test "deregistering is idempotent", %{mon: mon} do
    assert :ok = Monitor.deregister(mon, "nonexistent")
  end