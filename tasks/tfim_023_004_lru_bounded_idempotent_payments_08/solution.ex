  test "cache hit does not create a record and refreshes recency", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 3)

    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "x")
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "y")
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "z")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["x", "y", "z"]

    # touch "x": becomes MRU, y now LRU
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "x")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["y", "z", "x"]
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 3
  end