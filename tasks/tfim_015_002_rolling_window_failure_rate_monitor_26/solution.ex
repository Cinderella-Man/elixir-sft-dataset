  test "a deregistered registration's timer chain cannot drive a re-registration", %{mon: mon} do
    test_pid = self()

    # Arm a SHORT chain, then deregister before it fires: the armed timer (and
    # any queued {:check, "web"}) must die with the registration.
    RateMonitor.register(mon, "web", fn -> :ok end, 80)
    assert :ok = RateMonitor.deregister(mon, "web")

    # Re-register far out of firing range. Only a leftover 80ms chain could
    # possibly run this check within the observation window.
    RateMonitor.register(
      mon,
      "web",
      fn ->
        send(test_pid, :stale_chain_fired)
        :ok
      end,
      60_000
    )

    refute_receive :stale_chain_fired, 400

    assert {:ok, %{status: :pending, checks_in_window: 0, last_check_at: nil}} =
             RateMonitor.status(mon, "web")
  end