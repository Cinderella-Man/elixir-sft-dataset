  test "pool_size defaults to 3 idle workers", _context do
    pool =
      start_supervised!(
        {RetryPool, name: :added_default_pool},
        id: :added_default
      )

    status = RetryPool.status(pool)
    assert status.idle_workers == 3
    assert status.busy_workers == 0
  end