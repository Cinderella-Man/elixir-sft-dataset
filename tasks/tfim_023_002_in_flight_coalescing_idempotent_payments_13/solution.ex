  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = CoalescingPayments.process_payment(pid, @valid)
    {:ok, r2} = CoalescingPayments.process_payment(pid, @valid)
    {:ok, r3} = CoalescingPayments.process_payment(pid, @valid)
    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end