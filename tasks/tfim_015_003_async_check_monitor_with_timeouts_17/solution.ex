  test "statuses returns a map of all registered services", %{mon: mon} do
    AsyncMonitor.register(mon, "web", CheckFn.build("web"), 1_000)
    AsyncMonitor.register(mon, "db", CheckFn.build("db"), 2_000)
    AsyncMonitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = AsyncMonitor.statuses(mon)
    assert Map.keys(all) |> Enum.sort() == ["cache", "db", "web"]

    for {_name, info} <- all do
      assert info.status == :pending
    end
  end