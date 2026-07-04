  test "expired idempotency key allows reprocessing", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "ttl")
    Clock.advance(10_001)
    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "ttl")

    assert first.id != second.id
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end