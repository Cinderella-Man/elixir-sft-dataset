  test "max_queue defaults to 10 pending tasks", _context do
    pool =
      start_supervised!(
        {RetryPool, name: :added_maxq_pool},
        id: :added_maxq
      )

    gate = self()

    for _ <- 1..3 do
      {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    end

    workers =
      for _ <- 1..3 do
        assert_receive {:ready, w}, 1_000
        w
      end

    for _ <- 1..10 do
      {:ok, _} = RetryPool.submit(pool, quick_task(:filler))
    end

    assert {:error, :queue_full} = RetryPool.submit(pool, quick_task(:overflow))

    Enum.each(workers, &release/1)
  end