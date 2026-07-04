  test "different idempotency keys create separate records", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params, "key-1")
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params, "key-2")

    assert r1.id != r2.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end