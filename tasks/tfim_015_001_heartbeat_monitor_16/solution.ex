  test "statuses returns a map of all registered services", %{mon: mon} do
    Monitor.register(mon, "web", CheckFn.build("web"), 1_000)
    Monitor.register(mon, "db", CheckFn.build("db"), 2_000)
    Monitor.register(mon, "cache", CheckFn.build("cache"), 500)

    all = Monitor.statuses(mon)
    assert Map.keys(all) |> Enum.sort() == ["cache", "db", "web"]

    for {_name, info} <- all do
      assert info.status == :pending
    end
  end