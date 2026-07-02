  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = IdempotentPayments.process_payment(pid, @valid_params)

    assert resp.amount == 5000
    assert resp.currency == "USD"
    assert resp.recipient == "merchant_42"
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
  end