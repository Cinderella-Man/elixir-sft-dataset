  test "cleanup removes expired entries but keeps payment records", %{pid: pid} do
    for i <- 1..30 do
      StrictIdempotentPayments.process_payment(pid, @valid, "batch-#{i}")
    end

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    Clock.advance(10_001)

    # Trigger the sweep manually via the documented :cleanup message. A
    # GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that payment records survive cleanup while
    # expired idempotency entries do not.
    send(pid, :cleanup)

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    # Replaying an expired key creates a fresh record rather than a cache hit
    {:ok, _} = StrictIdempotentPayments.process_payment(pid, @valid, "batch-1")
    assert length(StrictIdempotentPayments.get_payments(pid)) == 31
    assert Process.alive?(pid)
  end