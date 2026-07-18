  test "extending maintenance before expiry keeps it alive past the old deadline", %{mon: mon} do
    check = CheckFn.build("db")
    ManagedMonitor.register(mon, "db", check, 60_000)

    # Enter a SHORT maintenance, then immediately replace it with a LONG one.
    # The replaced (short) duration's real expiry timer must never act: well
    # after the old deadline the service must still be in maintenance, with no
    # :maintenance_ended fired. (The bookkeeping test below cannot catch this —
    # it never lets the replaced timer's real delay elapse.)
    ManagedMonitor.maintenance(mon, "db", 60)
    ManagedMonitor.maintenance(mon, "db", 60_000)

    Process.sleep(250)

    # The status call synchronizes: any stale expiry queued by the old timer
    # has been processed by the time it returns.
    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:maintenance_ended) == 0

    # A manual resume must also retire the pending expiry: a FRESH maintenance
    # session afterwards survives the resumed session's old deadline too.
    assert :ok = ManagedMonitor.resume(mon, "db")
    ManagedMonitor.maintenance(mon, "db", 60)
    assert :ok = ManagedMonitor.resume(mon, "db")
    ManagedMonitor.maintenance(mon, "db", 60_000)
    Process.sleep(250)

    assert {:ok, %{status: :maintenance}} = ManagedMonitor.status(mon, "db")
    assert Notifications.count_event(:maintenance_ended) == 0
  end