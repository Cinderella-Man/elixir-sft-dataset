  test "invalid params cached under a key shadow later valid params until expiry", %{pid: pid} do
    assert {:error, :invalid_params} =
             CoalescingPayments.process_payment(pid, %{amount: 100}, "poisoned")

    assert CoalescingPayments.in_flight_count(pid) == 0

    assert {:error, :invalid_params} =
             CoalescingPayments.process_payment(pid, @valid, "poisoned")

    assert Calls.count() == 0
    assert CoalescingPayments.get_payments(pid) == []

    Clock.advance(10_001)
    assert {:ok, _} = CoalescingPayments.process_payment(pid, @valid, "poisoned")
    assert Calls.count() == 1
  end