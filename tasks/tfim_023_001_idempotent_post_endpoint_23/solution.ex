  test "default ttl_ms remembers idempotency keys for 24 hours", %{pid: _pid} do
    {:ok, server} =
      IdempotentPayments.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, first} = IdempotentPayments.process_payment(server, @valid_params, "default-ttl")

    Clock.advance(86_399_999)

    assert {:ok, ^first} =
             IdempotentPayments.process_payment(server, @valid_params, "default-ttl")

    assert length(IdempotentPayments.get_payments(server)) == 1

    Clock.advance(2)
    {:ok, later} = IdempotentPayments.process_payment(server, @valid_params, "default-ttl")
    assert later.id != first.id
    assert length(IdempotentPayments.get_payments(server)) == 2
  end