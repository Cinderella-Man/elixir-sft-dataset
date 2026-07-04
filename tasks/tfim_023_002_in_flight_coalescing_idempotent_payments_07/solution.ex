  test "different idempotency keys create separate records", %{pid: pid} do
    {:ok, r1} = CoalescingPayments.process_payment(pid, @valid, "key-1")
    {:ok, r2} = CoalescingPayments.process_payment(pid, @valid, "key-2")

    assert r1.id != r2.id
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end