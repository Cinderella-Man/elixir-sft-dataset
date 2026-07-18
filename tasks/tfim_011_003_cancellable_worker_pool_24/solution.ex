  test "queue keeps FIFO order after a middle task is cancelled", %{pool: pool} do
    gate = self()
    collector = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3) with three ordered tasks.
    {:ok, _q1} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 1}) && 1 end)
    {:ok, q2} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 2}) && 2 end)
    {:ok, _q3} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 3}) && 3 end)

    # Cancel the middle task; the survivors must still run in submission order.
    assert :ok = CancellablePool.cancel(pool, q2)

    release(w1)
    assert_receive {:ran, 1}, 1_000

    release(w2)
    assert_receive {:ran, 3}, 1_000

    # The cancelled middle task must never execute.
    refute_receive {:ran, 2}, 300
  end