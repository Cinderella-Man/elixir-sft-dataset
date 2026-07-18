  test "re-entering maintenance replaces the duration", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 5_000)
    assert {:ok, %{maintenance_ends_at: 5_000}} = ManagedMonitor.status(mon, "db")

    Clock.advance(2_000)
    ManagedMonitor.maintenance(mon, "db", 10_000)
    assert {:ok, %{maintenance_ends_at: 12_000}} = ManagedMonitor.status(mon, "db")

    assert Notifications.count_event(:maintenance_started) == 2
  end