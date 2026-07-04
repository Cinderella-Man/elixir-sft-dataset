  test "returns error for missing required fields", %{pid: pid} do
    assert {:error, :invalid_params} =
             StrictIdempotentPayments.process_payment(pid, %{amount: 100})
  end