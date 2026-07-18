  test "nil key creates a new record on every call even with identical params", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, nil)

    assert r1.id != r2.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
    assert {:ok, _} = StrictIdempotentPayments.get_payment(pid, r1.id)
    assert {:ok, _} = StrictIdempotentPayments.get_payment(pid, r2.id)
  end