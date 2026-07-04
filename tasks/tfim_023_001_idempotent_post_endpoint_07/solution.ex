  test "expired idempotency key allows reprocessing", %{pid: pid} do
    key = "idem-ttl"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Advance past the TTL (10_000 ms configured in setup)
    Clock.advance(10_001)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # A new payment record should have been created
    assert first.id != second.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end