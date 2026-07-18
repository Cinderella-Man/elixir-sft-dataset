  test "maintenance mode reports :maintenance status", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert :ok = ManagedMonitor.maintenance(mon, "db", 10_000)
    assert {:ok, info} = ManagedMonitor.status(mon, "db")
    assert info.status == :maintenance
    assert info.maintenance_ends_at == 11_000
  end