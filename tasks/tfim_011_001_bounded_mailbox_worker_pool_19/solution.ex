  test "pool starts three workers by default", _context do
    name = :"defsize_#{:erlang.unique_integer([:positive])}"

    pool =
      start_supervised!({WorkerPool, name: name}, id: :defsize_pool)

    status = WorkerPool.status(pool)
    assert status.idle_workers == 3
    assert status.busy_workers == 0
    assert status.queue_length == 0
  end