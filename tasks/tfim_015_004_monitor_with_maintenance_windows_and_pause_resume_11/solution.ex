  test "pausing a service changes its reported status to :paused", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    # Get to :up first
    Clock.advance(1_000)
    trigger_check(mon, "web")
    assert {:ok, %{status: :up}} = ManagedMonitor.status(mon, "web")

    assert :ok = ManagedMonitor.pause(mon, "web")
    assert {:ok, %{status: :paused}} = ManagedMonitor.status(mon, "web")
  end