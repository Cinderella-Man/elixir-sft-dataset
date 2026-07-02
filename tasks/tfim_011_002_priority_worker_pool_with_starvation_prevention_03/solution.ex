  test "submit and await tasks at different priorities", %{pool: pool} do
    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:hi), :high)
    {:ok, r2} = PriorityWorkerPool.submit(pool, quick_task(:lo), :low)
    {:ok, r3} = PriorityWorkerPool.submit(pool, quick_task(:mid), :normal)

    assert {:ok, :hi} = PriorityWorkerPool.await(pool, r1, 1_000)
    assert {:ok, :lo} = PriorityWorkerPool.await(pool, r2, 1_000)
    assert {:ok, :mid} = PriorityWorkerPool.await(pool, r3, 1_000)
  end