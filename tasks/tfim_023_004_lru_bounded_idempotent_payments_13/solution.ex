  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, @valid)
    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end