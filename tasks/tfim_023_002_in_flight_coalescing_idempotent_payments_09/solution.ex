  test "returns error for missing required fields without calling processor", %{pid: pid} do
    assert {:error, :invalid_params} = CoalescingPayments.process_payment(pid, %{amount: 100})
    assert Calls.count() == 0
  end