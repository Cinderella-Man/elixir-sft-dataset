  test "await uses its default timeout when none is given", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, quick_task(:defaulted))
    assert {:ok, :defaulted} = WorkerPool.await(pool, ref)
  end