  test "cleanup_interval_ms sweeps expired entries without an explicit message" do
    {:ok, server} =
      IdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: 20
      )

    {:ok, first} = IdempotentPayments.process_payment(server, @valid_params, "auto-key")

    # The entry expires at 10_000; leave the clock there long enough for several
    # scheduled sweeps to fire on their own.
    Clock.set(10_001)
    Process.sleep(150)

    # Rewind the injected clock: the entry, if it had survived, would still be a
    # live cache hit. A new record proves an automatic sweep purged it.
    Clock.set(0)

    {:ok, second} = IdempotentPayments.process_payment(server, @valid_params, "auto-key")
    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(server)) == 2
  end