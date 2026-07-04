  test "error results are cached by fingerprint; different params under same key conflict", %{
    pid: pid
  } do
    r1 = StrictIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    r2 = StrictIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")

    assert r1 == {:error, :invalid_params}
    assert r2 == {:error, :invalid_params}
    assert StrictIdempotentPayments.get_payments(pid) == []

    # Same key, different (this time valid) params -> conflict, not a fresh record
    conflict = StrictIdempotentPayments.process_payment(pid, @valid, "bad")
    assert conflict == {:error, :idempotency_key_conflict}
    assert StrictIdempotentPayments.get_payments(pid) == []
  end