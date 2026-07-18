  test "custom window_size and threshold are respected", %{mon: mon} do
    check = CheckFn.build("cache")
    # window_size=4, threshold=0.75 → need 3/4 errors
    RateMonitor.register(mon, "cache", check, 500, window_size: 4, threshold: 0.75)

    # 2 errors, 2 ok → rate = 0.5 < 0.75
    CheckFn.set_result("cache", {:error, :conn_refused})
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    CheckFn.set_result("cache", :ok)
    Clock.advance(500)
    trigger_check(mon, "cache")
    Clock.advance(500)
    trigger_check(mon, "cache")

    assert {:ok, %{status: :up}} = RateMonitor.status(mon, "cache")
    assert Notifications.count() == 0
  end