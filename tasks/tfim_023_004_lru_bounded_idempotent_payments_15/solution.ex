  test "response ids follow the counter-based pay_N form in order", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid, "key-a")
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r3.id == "pay_3"
    assert r2.currency == "USD"
    assert r2.recipient == "merchant_42"
    assert r2.status == "completed"
    assert r2.created_at == Clock.now()
  end