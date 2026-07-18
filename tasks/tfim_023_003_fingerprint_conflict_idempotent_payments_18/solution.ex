  test "cleanup keeps unexpired entries while purging expired ones", %{pid: pid} do
    {:ok, old} = StrictIdempotentPayments.process_payment(pid, @valid, "old-key")
    Clock.advance(6_000)
    {:ok, fresh} = StrictIdempotentPayments.process_payment(pid, @valid, "fresh-key")
    Clock.advance(5_000)

    send(pid, :cleanup)

    # "fresh-key" expires at 16_000 and is still live at 11_000: cache hit.
    {:ok, replay} = StrictIdempotentPayments.process_payment(pid, @valid, "fresh-key")
    assert replay == fresh
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2

    # "old-key" expired at 10_000 and was purged: reprocessed fresh.
    {:ok, again} = StrictIdempotentPayments.process_payment(pid, @valid, "old-key")
    assert again.id != old.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 3
  end