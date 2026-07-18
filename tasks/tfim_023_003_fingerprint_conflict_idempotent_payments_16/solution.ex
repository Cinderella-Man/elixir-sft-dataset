  test "ttl_ms defaults to 86,400,000 ms when the option is omitted" do
    {:ok, pid} =
      StrictIdempotentPayments.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")

    Clock.advance(86_399_999)
    {:ok, cached} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")
    assert cached == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    Clock.advance(2)
    {:ok, fresh} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")
    assert fresh.id != first.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end