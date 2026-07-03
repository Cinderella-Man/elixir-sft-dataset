  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = CoalescingPayments.process_payment(pid, @valid)
    assert resp.amount == 5000
    assert resp.currency == "USD"
    assert resp.recipient == "merchant_42"
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
    assert Calls.count() == 1
  end