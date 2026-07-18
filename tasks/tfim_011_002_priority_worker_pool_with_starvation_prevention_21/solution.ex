  test "max_queue of 0 means no queuing", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 0, promote_after_ms: 60_000, name: :no_queue_priority_pool},
        id: :no_queue
      )

    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:nope), :high)

    release(w1)
  end