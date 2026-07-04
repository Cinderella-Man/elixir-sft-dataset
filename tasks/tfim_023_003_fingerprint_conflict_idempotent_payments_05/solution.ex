  test "different keys create separate records regardless of params", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid, "k1")
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "k2")

    assert r1.id != r2.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end