  test "deregistering stops timer-driven checks from running", %{mon: mon} do
    check = reporting_check("cancelled", :ok)
    assert :ok = Monitor.register(mon, "cancelled", check, 20)

    assert_receive {:checked, "cancelled"}, 2_000

    assert :ok = Monitor.deregister(mon, "cancelled")
    drain_checks()

    # No pending or future check for a deregistered service may run its
    # check function, even though several intervals go by.
    refute_receive {:checked, "cancelled"}, 300
  end