  test "get_payment retrieves by id and reports not found", %{pid: pid} do
    {:ok, resp} = StrictIdempotentPayments.process_payment(pid, @valid)
    assert {:ok, found} = StrictIdempotentPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert {:error, :not_found} = StrictIdempotentPayments.get_payment(pid, "pay_nope")
  end