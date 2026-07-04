  test "error results are cached under the key and occupy a slot", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    r1 = BoundedIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    r2 = BoundedIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    assert r1 == {:error, :invalid_params}
    assert r2 == {:error, :invalid_params}
    assert BoundedIdempotentPayments.get_payments(pid) == []

    # "bad" occupies a slot in the LRU store
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["bad"]
  end