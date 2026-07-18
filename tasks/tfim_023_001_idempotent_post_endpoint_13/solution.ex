  test "get_payment returns error for unknown id", %{pid: pid} do
    assert {:error, :not_found} = IdempotentPayments.get_payment(pid, "pay_nonexistent")
  end