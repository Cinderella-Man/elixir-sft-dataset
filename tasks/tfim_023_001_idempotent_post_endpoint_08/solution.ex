  test "key is still valid just before expiry", %{pid: pid} do
    key = "idem-edge"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Advance to just before TTL expires
    Clock.advance(9_999)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    assert first == second
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end