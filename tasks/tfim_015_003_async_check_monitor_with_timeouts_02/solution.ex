  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = AsyncMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.consecutive_failures == 0
    assert info.last_check_at == nil
    assert info.check_in_flight == false
  end