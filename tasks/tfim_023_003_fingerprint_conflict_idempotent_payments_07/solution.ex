  test "key is still valid just before expiry", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "edge")
    Clock.advance(9_999)
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "edge")

    assert first == second
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end