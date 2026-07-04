  test "expired key allows reprocessing with new params (no conflict)", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "ttl")
    Clock.advance(10_001)

    {:ok, second} =
      StrictIdempotentPayments.process_payment(
        pid,
        %{amount: 111, currency: "GBP", recipient: "new_merchant"},
        "ttl"
      )

    assert first.id != second.id
    assert second.amount == 111
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end