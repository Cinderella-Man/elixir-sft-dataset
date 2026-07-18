  test "get_payments lists records oldest first", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 1})
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 2})
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 3})

    records = BoundedIdempotentPayments.get_payments(pid)
    assert Enum.map(records, & &1.id) == [r1.id, r2.id, r3.id]
    assert Enum.map(records, & &1.amount) == [1, 2, 3]
  end