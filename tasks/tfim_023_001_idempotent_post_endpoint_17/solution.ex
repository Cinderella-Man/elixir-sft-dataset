  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params)

    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end