  test "same key returns cached result without a duplicate record", %{pid: pid} do
    {:ok, first} = BoundedIdempotentPayments.process_payment(pid, @valid, "k")
    {:ok, second} = BoundedIdempotentPayments.process_payment(pid, @valid, "k")
    assert first == second
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 1
  end