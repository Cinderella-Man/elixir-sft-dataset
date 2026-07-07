  test "notification fires again on a second down after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    ManagedMonitor.register(mon, "api", check, 1_000)

    # First down
    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    # Recover
    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    # Second down
    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count_event(:down) == 2

    down_events =
      Notifications.all()
      |> Enum.filter(fn {_, event, _} -> event == :down end)

    assert [{"api", :down, :crash}, {"api", :down, :oom}] = down_events
  end