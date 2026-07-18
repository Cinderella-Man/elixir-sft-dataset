  test "omitting :pool_size starts three workers", _context do
    name = :"pool_default_size_#{System.pid()}_#{System.unique_integer([:positive])}"
    pool = start_supervised!({PriorityWorkerPool, name: name}, id: :default_size)

    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers == 3
    assert status.busy_workers == 0
    assert status.total_queue_length == 0
  end