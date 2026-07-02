  test "submit and await a simple task at default priority", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(42))
    assert {:ok, 42} = PriorityWorkerPool.await(pool, ref, 1_000)
  end