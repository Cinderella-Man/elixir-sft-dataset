  test "get_payments lists records in creation order, oldest first", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid, "o1")
    Clock.advance(5)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "o2")
    Clock.advance(5)
    {:ok, r3} = StrictIdempotentPayments.process_payment(pid, @valid, "o3")

    ids = Enum.map(StrictIdempotentPayments.get_payments(pid), & &1.id)
    assert ids == [r1.id, r2.id, r3.id]
  end