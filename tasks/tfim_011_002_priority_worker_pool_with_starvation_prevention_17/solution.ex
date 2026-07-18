  test "worker count is restored after crash", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "die" end)
    PriorityWorkerPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end