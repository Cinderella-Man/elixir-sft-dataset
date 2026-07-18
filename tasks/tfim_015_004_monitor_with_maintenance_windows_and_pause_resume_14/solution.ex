  test "resume returns :not_paused for active services", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    assert {:error, :not_paused} = ManagedMonitor.resume(mon, "web")
  end