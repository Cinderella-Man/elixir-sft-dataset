  test "newly registered service starts in :pending status", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = RateMonitor.register(mon, "web", check, 5_000)

    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.failure_rate == 0.0
    assert info.checks_in_window == 0
    assert info.last_check_at == nil
  end