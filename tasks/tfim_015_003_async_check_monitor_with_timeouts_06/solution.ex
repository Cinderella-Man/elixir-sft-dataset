  test "service goes :down after max_failures consecutive failures (default 3)", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    AsyncMonitor.register(mon, "db", check, 1_000)

    for _i <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             AsyncMonitor.status(mon, "db")
  end