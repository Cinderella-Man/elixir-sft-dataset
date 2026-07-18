  test "cleanup far past the TTL keeps an in-flight key and still replies to its waiter" do
    test_pid = self()

    processor = fn _params ->
      send(test_pid, {:worker, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    spawn(fn ->
      send(test_pid, {:res, CoalescingPayments.process_payment(pid, @valid, "long")})
    end)

    assert_receive {:worker, worker}, 2000

    Clock.advance(10_000_000)
    send(pid, :cleanup)

    # The synchronous call proves the cleanup ahead of it was handled.
    assert CoalescingPayments.in_flight_count(pid) == 1

    send(worker, :release)

    assert_receive {:res, {:ok, resp}}, 2000
    assert resp.status == "completed"
    assert CoalescingPayments.in_flight_count(pid) == 0
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end