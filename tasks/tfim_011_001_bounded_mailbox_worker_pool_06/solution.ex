  test "queue rejects when full", %{pool: pool} do
    gate = self()

    # Fill 2 workers
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3)
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q1))
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q2))
    {:ok, _} = WorkerPool.submit(pool, quick_task(:q3))

    # This should be rejected
    assert {:error, :queue_full} = WorkerPool.submit(pool, quick_task(:overflow))

    # Cleanup
    release(w1)
    release(w2)
  end