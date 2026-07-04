  test "status shows per-priority queue counts", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:h1), :high)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:n1), :normal)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:l1), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.queue_high == 1
    assert status.queue_normal == 1
    assert status.queue_low == 1
    assert status.total_queue_length == 3

    release(w1)
    release(w2)
  end