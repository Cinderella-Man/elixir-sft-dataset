  test "cleanup removes expired idempotency entries but keeps payment records", %{pid: pid} do
    for i <- 1..20 do
      CoalescingPayments.process_payment(pid, @valid, "batch-#{i}")
    end

    assert length(CoalescingPayments.get_payments(pid)) == 20

    Clock.advance(10_001)
    send(pid, :cleanup)

    # A synchronous call cannot be answered until the cleanup message ahead of it
    # has been handled, and it shows that no work is left in flight.
    assert CoalescingPayments.in_flight_count(pid) == 0

    assert length(CoalescingPayments.get_payments(pid)) == 20

    # The expired key no longer short-circuits: the payment is processed again.
    {:ok, _} = CoalescingPayments.process_payment(pid, @valid, "batch-1")
    assert length(CoalescingPayments.get_payments(pid)) == 21
  end