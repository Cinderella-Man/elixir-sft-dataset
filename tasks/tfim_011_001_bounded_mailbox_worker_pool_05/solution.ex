  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    # Fill both workers with blocking tasks
    {:ok, _r1} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _r2} = WorkerPool.submit(pool, blocking_task(gate))

    # Wait for both workers to be running
    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # These should be queued (not rejected)
    {:ok, r3} = WorkerPool.submit(pool, quick_task(:queued_1))
    {:ok, r4} = WorkerPool.submit(pool, quick_task(:queued_2))

    # Verify queue status
    status = WorkerPool.status(pool)
    assert status.busy_workers == 2
    assert status.idle_workers == 0
    assert status.queue_length >= 2

    # Release workers so queued tasks execute
    release(w1)
    release(w2)

    assert {:ok, :queued_1} = WorkerPool.await(pool, r3, 2_000)
    assert {:ok, :queued_2} = WorkerPool.await(pool, r4, 2_000)
  end