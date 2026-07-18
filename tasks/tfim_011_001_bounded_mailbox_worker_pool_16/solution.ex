  test "max_queue of 0 means no queuing — reject immediately when busy", _context do
    pool =
      start_supervised!(
        {WorkerPool, pool_size: 1, max_queue: 0, name: :no_queue_pool},
        id: :no_queue
      )

    gate = self()

    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    # Worker is busy, queue is 0 → reject
    assert {:error, :queue_full} = WorkerPool.submit(pool, quick_task(:nope))

    release(w1)
  end