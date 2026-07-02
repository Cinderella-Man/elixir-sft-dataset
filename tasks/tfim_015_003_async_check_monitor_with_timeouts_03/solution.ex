  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = AsyncMonitor.register(mon, "web", check, 5_000)
  end