  test "status updates as tasks are submitted", %{pool: pool} do
    gate = self()

    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    status = WorkerPool.status(pool)
    assert status.busy_workers == 1
    assert status.idle_workers == 1
    assert status.queue_length == 0

    release(w1)
  end