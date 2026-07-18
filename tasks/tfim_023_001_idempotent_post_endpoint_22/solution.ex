  test "created_at is taken from the injected clock at processing time", %{pid: pid} do
    Clock.set(777_000)
    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params)
    assert first.created_at == 777_000

    Clock.set(1_234_567)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, "clock-key")
    assert second.created_at == 1_234_567

    assert {:ok, stored} = IdempotentPayments.get_payment(pid, second.id)
    assert stored.created_at == 1_234_567
  end