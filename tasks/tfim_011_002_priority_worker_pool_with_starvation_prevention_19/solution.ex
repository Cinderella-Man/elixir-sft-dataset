  test "omitting :max_queue allows ten pending tasks and rejects the eleventh", _context do
    name = :"pool_default_queue_#{System.pid()}_#{System.unique_integer([:positive])}"
    pool = start_supervised!({PriorityWorkerPool, name: name}, id: :default_queue)

    gate = self()

    # With the default pool of three workers, three blocking tasks leave the
    # pool fully busy so every further submission has to be queued.
    blocked =
      for _ <- 1..3 do
        {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
        assert_receive {:ready, worker}, 1_000
        worker
      end

    for _ <- 1..10 do
      {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:filler), :normal)
    end

    assert PriorityWorkerPool.status(pool).total_queue_length == 10
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:over), :high)

    Enum.each(blocked, &release/1)
  end