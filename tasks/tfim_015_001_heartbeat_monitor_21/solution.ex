  test "the monitor re-arms its timer so checks repeat every interval", %{mon: mon} do
    check = reporting_check("repeating", :ok)
    assert :ok = Monitor.register(mon, "repeating", check, 20)

    # Each completed check schedules the next one, so reports keep arriving
    # without any help from the test.
    assert_receive {:checked, "repeating"}, 2_000
    assert_receive {:checked, "repeating"}, 2_000
    assert_receive {:checked, "repeating"}, 2_000
  end