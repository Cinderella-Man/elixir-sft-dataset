  test "custom max_failures is respected", %{mon: mon} do
    CheckFn.set_result("cache", {:error, :conn_refused})
    check = CheckFn.build("cache")
    AsyncMonitor.register(mon, "cache", check, 500, max_failures: 5)

    for _ <- 1..4 do
      Clock.advance(500)
      trigger_check(mon, "cache")
    end

    assert {:ok, %{status: status}} = AsyncMonitor.status(mon, "cache")
    refute status == :down, "should not be :down after only 4 failures with max_failures=5"

    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :down, consecutive_failures: 5}} =
             AsyncMonitor.status(mon, "cache")

    assert Notifications.count() == 1
  end