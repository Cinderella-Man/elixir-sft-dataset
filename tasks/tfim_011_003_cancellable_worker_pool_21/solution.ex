  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {CancellablePool, pool_size: 1, max_queue: 2, name: :single_cancel_pool},
        id: :single
      )

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:only))
    assert {:ok, :only} = CancellablePool.await(pool, r1, 1_000)
  end