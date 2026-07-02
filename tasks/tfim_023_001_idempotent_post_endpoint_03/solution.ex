  test "requests without idempotency key always create new records", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)

    assert r1.id != r2.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end