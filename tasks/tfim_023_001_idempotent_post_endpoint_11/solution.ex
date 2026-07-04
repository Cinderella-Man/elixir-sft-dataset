  test "get_payment retrieves a specific record by id", %{pid: pid} do
    {:ok, resp} = IdempotentPayments.process_payment(pid, @valid_params)

    assert {:ok, found} = IdempotentPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert found.amount == 5000
  end