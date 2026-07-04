  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = RetryPool.submit(pool, quick_task(:queued))

    status = RetryPool.status(pool)
    assert status.queue_length >= 1

    release(w1)
    release(w2)

    assert {:ok, :queued} = RetryPool.await(pool, r3, 2_000)
  end