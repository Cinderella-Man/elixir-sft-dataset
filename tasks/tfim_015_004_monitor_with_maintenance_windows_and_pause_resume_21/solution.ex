  test "maintenance can be resumed manually before expiry", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 60_000)
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")

    ManagedMonitor.resume(mon, "db")
    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "db")

    # Stale maintenance_end should be discarded
    send(mon, {:maintenance_end, "db"})
    _ = ManagedMonitor.status(mon, "db")

    # Should still be pending (not re-transitioned)
    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:maintenance_ended) == 0
  end