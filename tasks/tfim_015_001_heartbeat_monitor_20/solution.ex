  test "the monitor itself runs the first check only after interval_ms elapses", %{mon: mon} do
    check = reporting_check("timed", :ok)
    assert :ok = Monitor.register(mon, "timed", check, 300)

    # Registration alone must not run the check; it is scheduled for later.
    refute_receive {:checked, "timed"}, 100

    # Once the interval passes, the monitor's own timer runs the check.
    assert_receive {:checked, "timed"}, 2_000

    assert {:ok, %{status: :up}} = Monitor.status(mon, "timed")
  end