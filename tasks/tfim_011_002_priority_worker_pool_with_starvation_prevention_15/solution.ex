  test "pool remains functional after a worker crash", %{pool: pool} do
    {:ok, ref_crash} = PriorityWorkerPool.submit(pool, fn -> raise "kaboom" end)
    PriorityWorkerPool.await(pool, ref_crash, 2_000)

    Process.sleep(100)

    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = PriorityWorkerPool.await(pool, ref, 1_000)
  end