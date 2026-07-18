  test "a finite cleanup_interval_ms sweeps periodically without disrupting service" do
    {:ok, pid} =
      StrictIdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: 10
      )

    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "live")

    # Several sweeps fire in this window; unexpired entries must survive them.
    Process.sleep(60)
    assert Process.alive?(pid)

    {:ok, cached} = StrictIdempotentPayments.process_payment(pid, @valid, "live")
    assert cached == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end