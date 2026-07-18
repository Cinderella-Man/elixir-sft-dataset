  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)

    assert :ok = Monitor.deregister(mon, "web")
    assert {:error, :not_found} = Monitor.status(mon, "web")
    assert Monitor.statuses(mon) == %{}
  end