  test "response after expiry is re-cached under the same key with a fresh TTL", %{pid: pid} do
    key = "idem-recache"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    Clock.advance(10_001)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert second.id != first.id

    # The second response must now be cached for a full fresh TTL window.
    Clock.advance(9_999)
    assert {:ok, ^second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end