  test "key is expired exactly at the ttl boundary", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "boundary")

    # Entry expiry is 0 + ttl_ms (10_000): at exactly 10_000 the TTL has elapsed,
    # so the replay must be processed fresh rather than served from the cache.
    Clock.advance(10_000)
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "boundary")

    assert second.id != first.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end