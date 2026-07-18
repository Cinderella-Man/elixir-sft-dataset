  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {WorkerPool, pool_size: 1, max_queue: 2, name: :single_worker_pool},
        id: :single
      )

    {:ok, r1} = WorkerPool.submit(pool, quick_task(:only))
    assert {:ok, :only} = WorkerPool.await(pool, r1, 1_000)
  end