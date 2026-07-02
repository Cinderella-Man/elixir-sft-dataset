  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = ManagedMonitor.register(mon, "web", check, 5_000)
  end