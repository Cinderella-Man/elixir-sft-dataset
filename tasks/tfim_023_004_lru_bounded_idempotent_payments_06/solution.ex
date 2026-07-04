  test "eviction: a new key at capacity drops the least-recently-used key", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    {:ok, _a} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    {:ok, _b} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["a", "b"]

    # "c" overflows -> evicts LRU ("a")
    {:ok, _c} = BoundedIdempotentPayments.process_payment(pid, @valid, "c")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["b", "c"]

    # "a" was evicted -> reprocessed as a brand new record
    before = length(BoundedIdempotentPayments.get_payments(pid))
    {:ok, _a2} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert length(BoundedIdempotentPayments.get_payments(pid)) == before + 1
  end