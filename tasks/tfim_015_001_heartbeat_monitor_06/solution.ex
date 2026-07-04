  test "service goes :down after max_failures consecutive failures (default 3)", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    Monitor.register(mon, "db", check, 1_000)

    # Failure 1
    Clock.advance(1_000)
    trigger_check(mon, "db")
    assert {:ok, %{status: s1, consecutive_failures: 1}} = Monitor.status(mon, "db")
    # Should still be :pending or :up depending on implementation —
    # the key point is it's not :down yet
    assert s1 in [:pending, :up] or s1 != :down

    # Failure 2
    Clock.advance(1_000)
    trigger_check(mon, "db")
    assert {:ok, %{consecutive_failures: 2}} = Monitor.status(mon, "db")

    # Failure 3 → transitions to :down
    Clock.advance(1_000)
    trigger_check(mon, "db")

    assert {:ok, %{status: :down, consecutive_failures: 3}} =
             Monitor.status(mon, "db")
  end