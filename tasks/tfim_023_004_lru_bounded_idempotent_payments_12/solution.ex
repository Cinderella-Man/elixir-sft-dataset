  test "payment records are never evicted even as keys churn", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 3)

    for i <- 1..20 do
      BoundedIdempotentPayments.process_payment(pid, @valid, "key-#{i}")
    end

    # Only 3 keys retained, but all 20 payment records survive
    assert length(BoundedIdempotentPayments.keys_by_recency(pid)) == 3
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 20
  end