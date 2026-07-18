  test "pool started without options queues 10 tasks before rejecting", _context do
    gate = self()

    pool =
      start_supervised!({CancellablePool, name: unique_name(:default_queue_pool)},
        id: :default_queue
      )

    # Occupy all three default workers.
    for _ <- 1..3 do
      {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    end

    workers =
      for _ <- 1..3 do
        assert_receive {:ready, worker}, 1_000
        worker
      end

    # The default queue holds exactly 10 pending tasks.
    for i <- 1..10 do
      assert {:ok, _ref} = CancellablePool.submit(pool, quick_task(i))
    end

    assert CancellablePool.status(pool).queue_length == 10
    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    Enum.each(workers, &release/1)
  end