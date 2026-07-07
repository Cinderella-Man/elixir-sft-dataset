  test "high-priority queued tasks execute before normal and low", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue tasks in reverse priority order
    {:ok, _} =
      PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, :low}); :low end, :low)
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn -> send(collector, {:executed, :normal}); :normal end,
        :normal
      )
    {:ok, _} =
      PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, :high}); :high end, :high)

    # Release one worker at a time
    release(w1)
    assert_receive {:executed, :high}, 1_000

    release(w2)
    assert_receive {:executed, :normal}, 1_000

    # Third task runs on whichever finishes first
    assert_receive {:executed, :low}, 1_000
  end