  test "caller joining a pending key gets the group result even with invalid params" do
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

    first = Task.async(fn -> CoalescingPayments.process_payment(pid, @valid, "group") end)
    assert_receive {:worker, worker}, 2000

    spawn(fn ->
      send(test_pid, {:second, CoalescingPayments.process_payment(pid, %{junk: true}, "group")})
    end)

    # The joiner must block on the pending group, not be rejected as invalid_params.
    refute_receive {:second, _}, 200
    assert CoalescingPayments.in_flight_count(pid) == 1

    send(worker, :release)

    assert_receive {:second, {:ok, second}}, 2000
    assert {:ok, first_result} = Task.await(first, 2000)
    assert second == first_result
    assert second.recipient == "merchant_42"
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end