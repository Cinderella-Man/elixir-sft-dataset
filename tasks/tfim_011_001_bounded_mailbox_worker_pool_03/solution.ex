  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = WorkerPool.submit(pool, quick_task(:a))
    {:ok, r2} = WorkerPool.submit(pool, quick_task(:b))
    {:ok, r3} = WorkerPool.submit(pool, quick_task(:c))

    assert {:ok, :a} = WorkerPool.await(pool, r1, 1_000)
    assert {:ok, :b} = WorkerPool.await(pool, r2, 1_000)
    assert {:ok, :c} = WorkerPool.await(pool, r3, 1_000)
  end