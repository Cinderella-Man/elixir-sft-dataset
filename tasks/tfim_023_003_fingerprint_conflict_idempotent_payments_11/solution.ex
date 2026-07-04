  test "cleanup removes expired entries but keeps payment records", %{pid: pid} do
    for i <- 1..30 do
      StrictIdempotentPayments.process_payment(pid, @valid, "batch-#{i}")
    end

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    Clock.advance(10_001)
    send(pid, :cleanup)
    state = :sys.get_state(pid)
    assert map_size(state.idempotency_keys) == 0

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    {:ok, _} = StrictIdempotentPayments.process_payment(pid, @valid, "batch-1")
    assert length(StrictIdempotentPayments.get_payments(pid)) == 31
  end