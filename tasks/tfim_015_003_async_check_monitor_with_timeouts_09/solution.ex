  test "a check that exceeds timeout_ms is treated as a failure", %{mon: mon} do
    blocking = CheckFn.build_blocking()
    # Use very short timeout for testing.
    AsyncMonitor.register(mon, "slow", blocking, 1_000, timeout_ms: 15, max_failures: 1)

    Clock.advance(1_000)
    trigger_check_with_timeout(mon, "slow")

    assert {:ok, %{status: :down, consecutive_failures: c}} = AsyncMonitor.status(mon, "slow")
    assert c >= 1

    # Notification should have fired with reason :timeout.
    assert Notifications.count() >= 1
    [{_name, reason}] = Notifications.all() |> Enum.take(1)
    assert reason == :timeout
  end