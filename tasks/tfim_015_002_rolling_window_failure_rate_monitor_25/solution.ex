  test "unexpected messages are ignored and do not alter service state", %{mon: mon} do
    CheckFn.set_result("web", :ok)
    RateMonitor.register(mon, "web", CheckFn.build("web"), 5_000)

    send(mon, :some_unexpected_message)
    send(mon, {:not_a_check, "web"})

    # A synchronous call after the sends is processed strictly after them, so
    # it proves the process survived and no service state was disturbed.
    assert {:ok, info} = RateMonitor.status(mon, "web")
    assert info.status == :pending
    assert info.checks_in_window == 0
    assert info.last_check_at == nil
    assert Process.alive?(mon)
  end