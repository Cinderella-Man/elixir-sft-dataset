  test "error responses are also cached under idempotency key", %{pid: pid} do
    key = "idem-bad"

    result1 = IdempotentPayments.process_payment(pid, %{amount: 100}, key)
    result2 = IdempotentPayments.process_payment(pid, %{amount: 100}, key)

    assert result1 == {:error, :invalid_params}
    assert result2 == {:error, :invalid_params}

    # No payment records should have been created
    assert length(IdempotentPayments.get_payments(pid)) == 0
  end