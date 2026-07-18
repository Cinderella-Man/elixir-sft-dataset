  test "failure on one service does not affect another", %{mon: mon} do
    CheckFn.set_result("bad", {:error, :fail})
    CheckFn.set_result("good", :ok)
    Monitor.register(mon, "bad", CheckFn.build("bad"), 1_000)
    Monitor.register(mon, "good", CheckFn.build("good"), 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "bad")
      trigger_check(mon, "good")
    end

    assert {:ok, %{status: :down}} = Monitor.status(mon, "bad")
    assert {:ok, %{status: :up, consecutive_failures: 0}} = Monitor.status(mon, "good")
  end