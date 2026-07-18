  test "cleanup removes expired idempotency entries but keeps payment records", %{pid: pid} do
    # Create 50 payments with unique idempotency keys
    for i <- 1..50 do
      IdempotentPayments.process_payment(pid, @valid_params, "batch-#{i}")
    end

    assert length(IdempotentPayments.get_payments(pid)) == 50

    # Advance past TTL
    Clock.advance(10_001)

    # Trigger the sweep manually via the documented :cleanup message
    send(pid, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that payment records survive cleanup while
    # expired idempotency keys do not.
    assert length(IdempotentPayments.get_payments(pid)) == 50

    # Idempotency keys are gone — replaying old keys creates new records
    # instead of returning cached responses
    {:ok, _resp} = IdempotentPayments.process_payment(pid, @valid_params, "batch-1")
    {:ok, _resp} = IdempotentPayments.process_payment(pid, @valid_params, "batch-50")
    assert length(IdempotentPayments.get_payments(pid)) == 52
    assert Process.alive?(pid)
  end