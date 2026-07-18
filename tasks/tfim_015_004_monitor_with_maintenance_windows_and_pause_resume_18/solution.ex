  test "successes during maintenance still update health to :up", %{mon: mon} do
    CheckFn.set_result("db", {:error, :crash})
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 1_000)

    # Drive to :down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    # Enter maintenance and succeed
    ManagedMonitor.maintenance(mon, "db", 60_000)
    CheckFn.set_result("db", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "db")

    # Still shows :maintenance, but internal health is :up
    assert {:ok, %{status: :maintenance, consecutive_failures: 0}} =
             ManagedMonitor.status(mon, "db")
  end