  test "processor errors are cached under the idempotency key", %{} do
    {:ok, decline_pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: fn _ -> {:error, :gateway_declined} end
      )

    r1 = CoalescingPayments.process_payment(decline_pid, @valid, "bad")
    r2 = CoalescingPayments.process_payment(decline_pid, @valid, "bad")

    assert r1 == {:error, :gateway_declined}
    assert r2 == {:error, :gateway_declined}
    assert CoalescingPayments.get_payments(decline_pid) == []
  end