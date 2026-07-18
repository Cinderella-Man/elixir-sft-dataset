  test "cleanup_interval_ms :infinity disables automatic sweeps", %{pid: pid} do
    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, "infinity-key")

    Clock.set(10_001)
    Process.sleep(150)

    # No sweep can have run, so rewinding the clock restores the cache hit.
    Clock.set(0)

    assert {:ok, ^first} = IdempotentPayments.process_payment(pid, @valid_params, "infinity-key")
    assert length(IdempotentPayments.get_payments(pid)) == 1
    assert Process.alive?(pid)
  end