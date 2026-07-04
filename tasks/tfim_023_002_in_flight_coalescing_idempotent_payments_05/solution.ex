  test "completed key returns cached result without re-running processor", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "k")
    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "k")

    assert first == second
    assert Calls.count() == 1
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end