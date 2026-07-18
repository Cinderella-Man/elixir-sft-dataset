  test "queued tasks survive a worker crash and still run in order", %{pool: pool} do
    gate = self()
    collector = self()

    {:ok, ref_crash} = CancellablePool.submit(pool, crash_on_signal(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:crash_ready, crashing_worker}, 1_000
    assert_receive {:ready, blocked_worker}, 1_000

    {:ok, ref_q1} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 1}) && :q1 end)
    {:ok, ref_q2} = CancellablePool.submit(pool, fn -> send(collector, {:ran, 2}) && :q2 end)

    # Crash the worker while both tasks are still waiting in the queue.
    release(crashing_worker)

    assert {:error, {:task_crashed, _reason}} = CancellablePool.await(pool, ref_crash, 2_000)

    # The replacement worker must take the head of the queue.
    assert {:ok, :q1} = CancellablePool.await(pool, ref_q1, 2_000)
    assert_receive {:ran, 1}, 2_000

    # The remaining queued task runs once the other worker frees up.
    release(blocked_worker)
    assert {:ok, :q2} = CancellablePool.await(pool, ref_q2, 2_000)
    assert_receive {:ran, 2}, 2_000

    assert CancellablePool.status(pool).queue_length == 0
  end