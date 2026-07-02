  test "same idempotency key returns identical response without duplicate record", %{pid: pid} do
    key = "idem-abc-123"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Responses must be byte-for-byte identical
    assert first == second

    # Only one payment record should exist
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end