  test "key is expired exactly at its expiry timestamp", %{pid: pid} do
    key = "idem-exact-boundary"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # The entry was cached at t=0 with ttl_ms 10_000, so it expires at t=10_000.
    # At that exact instant the key is no longer remembered.
    Clock.advance(10_000)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end