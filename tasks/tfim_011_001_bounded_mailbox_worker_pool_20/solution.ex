  test "queue defaults to a capacity of ten pending tasks", _context do
    name = :"maxq_#{:erlang.unique_integer([:positive])}"

    pool =
      start_supervised!({WorkerPool, pool_size: 1, name: name}, id: :maxq_pool)

    gate = self()
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w}, 1_000

    for _ <- 1..10 do
      assert {:ok, _} = WorkerPool.submit(pool, quick_task(:queued))
    end

    assert {:error, :queue_full} = WorkerPool.submit(pool, quick_task(:overflow))
    release(w)
  end