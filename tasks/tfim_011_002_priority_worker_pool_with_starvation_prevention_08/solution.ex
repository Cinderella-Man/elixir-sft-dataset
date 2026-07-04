  test "queue rejects when full across all priorities", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 5)
    for _ <- 1..5 do
      {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:filler), :normal)
    end

    # All priorities should be rejected when queue is full
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :high)
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :low)

    release(w1)
    release(w2)
  end