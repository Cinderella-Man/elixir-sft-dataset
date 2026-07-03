  test "requests without idempotency key always create new records", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid)
    assert r1.id != r2.id
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 2
  end