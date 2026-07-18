  test "cleanup purges an entry whose expiry has been reached exactly", %{pid: pid} do
    {:ok, _first} = StrictIdempotentPayments.process_payment(pid, @valid, "exact")

    # The entry expires at 0 + 10_000. Sweeping at exactly 10_000 must drop it:
    # an entry is expired once its expiry timestamp has been reached.
    Clock.set(10_000)
    send(pid, :cleanup)
    # Mailbox ordering: this call is served only after the sweep completes.
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    # Probe from a moment at which a *surviving* entry would still be live
    # (9_999 < 10_000). Because the sweep dropped it, the key is unseen: a
    # differing-params request is processed fresh instead of conflicting.
    Clock.set(9_999)

    assert {:ok, replacement} =
             StrictIdempotentPayments.process_payment(
               pid,
               %{amount: 1, currency: "EUR", recipient: "other"},
               "exact"
             )

    assert replacement.amount == 1
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end