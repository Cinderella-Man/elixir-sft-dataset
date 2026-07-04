  test "recovery notification fires when service goes from :down to :up", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    ManagedMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    assert Notifications.count_event(:recovered) == 1

    recovery_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :recovered end)

    assert [{"api", :recovered, nil}] = recovery_events
  end