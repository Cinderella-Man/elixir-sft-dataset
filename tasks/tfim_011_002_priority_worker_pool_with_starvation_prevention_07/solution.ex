  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = PriorityWorkerPool.submit(pool, quick_task(:queued_1), :normal)
    {:ok, r4} = PriorityWorkerPool.submit(pool, quick_task(:queued_2), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.busy_workers == 2
    assert status.idle_workers == 0
    assert status.total_queue_length >= 2

    release(w1)
    release(w2)

    assert {:ok, :queued_1} = PriorityWorkerPool.await(pool, r3, 2_000)
    assert {:ok, :queued_2} = PriorityWorkerPool.await(pool, r4, 2_000)
  end