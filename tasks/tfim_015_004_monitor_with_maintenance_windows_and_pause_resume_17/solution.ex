  test "failures during maintenance do not increment the counter", %{mon: mon} do
    CheckFn.set_result("db", :ok)
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    Clock.advance(1_000)
    trigger_check(mon, "db")

    ManagedMonitor.maintenance(mon, "db", 60_000)

    CheckFn.set_result("db", {:error, :timeout})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{consecutive_failures: 0}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:down) == 0
  end