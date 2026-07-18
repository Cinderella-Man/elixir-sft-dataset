  test "pool remains functional after a worker crash", %{pool: pool} do
    # Submit a crashing task
    {:ok, ref_crash} = WorkerPool.submit(pool, fn -> raise "kaboom" end)
    WorkerPool.await(pool, ref_crash, 2_000)

    # Give the pool a moment to recover / restart the worker
    Process.sleep(100)

    # Pool should still work
    {:ok, ref} = WorkerPool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = WorkerPool.await(pool, ref, 1_000)
  end