  test "maintenance_started notification fires", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    ManagedMonitor.maintenance(mon, "db", 10_000)

    maint_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :maintenance_started end)

    assert [{"db", :maintenance_started, 10_000}] = maint_events
  end