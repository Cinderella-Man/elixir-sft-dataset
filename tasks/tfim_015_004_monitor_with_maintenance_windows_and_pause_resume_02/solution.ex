  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = ManagedMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
    assert info.maintenance_ends_at == nil
  end