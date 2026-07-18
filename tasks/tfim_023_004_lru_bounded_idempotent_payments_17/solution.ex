  test "clock only stamps :created_at and never drives recency order", %{pid: _pid} do
    {:ok, agent} = Agent.start_link(fn -> 500 end)
    clock = fn -> Agent.get_and_update(agent, fn n -> {n, n - 100} end) end
    {:ok, srv} = BoundedIdempotentPayments.start_link(clock: clock, max_keys: 2)

    {:ok, a} = BoundedIdempotentPayments.process_payment(srv, @valid, "a")
    {:ok, b} = BoundedIdempotentPayments.process_payment(srv, @valid, "b")
    assert a.created_at == 500
    assert b.created_at == 400

    # despite a descending clock, recency follows the internal tick
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["a", "b"]

    {:ok, c} = BoundedIdempotentPayments.process_payment(srv, @valid, "c")
    assert c.created_at == 300
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["b", "c"]
  end