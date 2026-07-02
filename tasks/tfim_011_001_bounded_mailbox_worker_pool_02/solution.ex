  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, quick_task(42))
    assert {:ok, 42} = WorkerPool.await(pool, ref, 1_000)
  end