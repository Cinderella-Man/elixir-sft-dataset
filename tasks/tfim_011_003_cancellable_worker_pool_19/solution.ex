  test "pool started without options has 3 idle workers and an empty queue", _context do
    pool =
      start_supervised!({CancellablePool, name: unique_name(:default_pool)}, id: :defaults)

    status = CancellablePool.status(pool)

    assert status.idle_workers == 3
    assert status.busy_workers == 0
    assert status.queue_length == 0
    assert status.cancelled_count == 0
  end