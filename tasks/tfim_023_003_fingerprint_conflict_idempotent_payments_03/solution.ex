  test "same key with same params returns identical response, one record", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "abc")
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "abc")

    assert first == second
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end