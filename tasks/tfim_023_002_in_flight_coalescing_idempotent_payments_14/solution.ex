  test "raising processor produces a cached exception error and the server survives" do
    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: fn _params -> raise ArgumentError, "gateway exploded" end
      )

    assert {:error, {:exception, "gateway exploded"}} =
             CoalescingPayments.process_payment(pid, @valid, "boom")

    # Cached like any other result: the processor is not re-run for the same key.
    assert {:error, {:exception, "gateway exploded"}} =
             CoalescingPayments.process_payment(pid, @valid, "boom")

    assert Process.alive?(pid)
    assert CoalescingPayments.get_payments(pid) == []
    assert CoalescingPayments.in_flight_count(pid) == 0
  end