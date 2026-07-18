  test "checks are skipped while paused", %{mon: mon} do
    CheckFn.set_result("web", {:error, :fail})
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    # Get to :up first with a success
    CheckFn.set_result("web", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "web")

    ManagedMonitor.pause(mon, "web")

    # Now set to failing and trigger checks
    CheckFn.set_result("web", {:error, :fail})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "web")
    end

    # Failures should NOT have been counted
    assert {:ok, %{consecutive_failures: 0}} = ManagedMonitor.status(mon, "web")
  end