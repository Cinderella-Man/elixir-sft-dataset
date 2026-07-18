  test "cached error key refreshes recency on hit and survives eviction", %{pid: _pid} do
    {:ok, srv} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    assert {:error, :invalid_params} =
             BoundedIdempotentPayments.process_payment(srv, %{amount: 100}, "bad")

    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "good")
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["bad", "good"]

    # a hit on the error key refreshes its recency, making "good" the LRU
    assert {:error, :invalid_params} =
             BoundedIdempotentPayments.process_payment(srv, %{amount: 100}, "bad")

    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["good", "bad"]

    # overflow evicts "good", not the touched error key
    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "third")
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["bad", "third"]
    assert length(BoundedIdempotentPayments.get_payments(srv)) == 2
  end