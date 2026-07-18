  test "worker count is restored after crash", %{pool: pool} do
    # Crash a worker
    {:ok, ref} = WorkerPool.submit(pool, fn -> raise "die" end)
    WorkerPool.await(pool, ref, 2_000)

    # Give supervisor time to restart
    Process.sleep(200)

    status = WorkerPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end