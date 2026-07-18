  test "failure on one service does not affect another", %{mon: mon} do
    CheckFn.set_result("bad", {:error, :fail})
    CheckFn.set_result("good", :ok)
    RateMonitor.register(mon, "bad", CheckFn.build("bad"), 1_000, window_size: 3, threshold: 0.6)
    RateMonitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "bad")
    assert {:ok, %{status: :up, failure_rate: +0.0}} = RateMonitor.status(mon, "good")
  end