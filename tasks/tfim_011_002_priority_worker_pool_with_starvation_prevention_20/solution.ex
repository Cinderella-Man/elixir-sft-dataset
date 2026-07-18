  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 2, promote_after_ms: 60_000, name: :single_priority_pool},
        id: :single
      )

    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:only), :low)
    assert {:ok, :only} = PriorityWorkerPool.await(pool, r1, 1_000)
  end