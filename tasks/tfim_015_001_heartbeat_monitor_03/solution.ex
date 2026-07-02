  test "cannot register the same service name twice", %{mon: mon} do
    check = CheckFn.build("web")
    assert :ok = Monitor.register(mon, "web", check, 5_000)
    assert {:error, :already_registered} = Monitor.register(mon, "web", check, 5_000)
  end