  test "interleaved idempotent and non-idempotent requests", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params, "key-A")
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params, "key-A")
    {:ok, r4} = IdempotentPayments.process_payment(pid, @valid_params)

    # r1 and r3 must be identical (same idempotency key)
    assert r1 == r3

    # r2 and r4 are independent new records
    assert r1.id != r2.id
    assert r2.id != r4.id

    # Total: r1 + r2 + r4 = 3 records (r3 is a cache hit)
    assert length(IdempotentPayments.get_payments(pid)) == 3
  end