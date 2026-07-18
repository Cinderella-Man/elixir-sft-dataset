  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 2, name: :single_retry_pool},
        id: :single
      )

    {:ok, r1} = RetryPool.submit(pool, quick_task(:only))
    assert {:ok, :only} = RetryPool.await(pool, r1, 1_000)
  end