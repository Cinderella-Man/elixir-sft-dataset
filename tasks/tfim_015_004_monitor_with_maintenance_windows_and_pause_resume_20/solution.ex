  test "maintenance auto-expires and restores health status", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    ManagedMonitor.maintenance(mon, "db", 5_000)
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")

    # Simulate the maintenance_end timer firing
    send(mon, {:maintenance_end, "db"})
    _ = ManagedMonitor.status(mon, "db")

    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "db")

    assert Notifications.count_event(:maintenance_ended) == 1
  end