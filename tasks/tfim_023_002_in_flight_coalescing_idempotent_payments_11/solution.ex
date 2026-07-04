  test "get_payment retrieves and reports not found", %{pid: pid} do
    {:ok, resp} = CoalescingPayments.process_payment(pid, @valid)
    assert {:ok, found} = CoalescingPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert {:error, :not_found} = CoalescingPayments.get_payment(pid, "pay_nope")
  end