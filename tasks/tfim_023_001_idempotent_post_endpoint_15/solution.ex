  test "cleanup purges an entry that reached its expiry timestamp exactly", %{pid: pid} do
    key = "sweep-boundary"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Entry cached at t=0 expires at t=10_000. Sweep at exactly that instant:
    # the entry has expired and must be purged.
    Clock.set(10_000)
    send(pid, :cleanup)
    # Ordered call: guarantees the sweep above has been handled already.
    assert length(IdempotentPayments.get_payments(pid)) == 1

    # The clock is injected, so move it back inside the original TTL window.
    # Had the sweep wrongly kept the entry, this replay would be a cache hit.
    Clock.set(5_000)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end