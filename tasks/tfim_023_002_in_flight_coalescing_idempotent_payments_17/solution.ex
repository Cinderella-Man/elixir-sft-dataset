  test "key whose expiry exactly equals the clock is reprocessed", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "edge")

    Clock.advance(10_000)

    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "edge")

    assert first.id != second.id
    assert Calls.count() == 2
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end