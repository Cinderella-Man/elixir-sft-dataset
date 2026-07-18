  test "declines and invalid params consume no counter so the first success is pay_1" do
    processor = fn _params ->
      Calls.bump()
      if Calls.count() == 1, do: {:error, :gateway_declined}, else: :ok
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    assert {:error, :gateway_declined} = CoalescingPayments.process_payment(pid, @valid)
    assert {:error, :invalid_params} = CoalescingPayments.process_payment(pid, %{amount: 1})

    assert {:ok, r1} = CoalescingPayments.process_payment(pid, @valid)
    assert {:ok, r2} = CoalescingPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert Enum.map(CoalescingPayments.get_payments(pid), & &1.id) == ["pay_1", "pay_2"]
  end