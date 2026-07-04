  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, slow_task(2_000, :late))
    assert {:error, :timeout} = WorkerPool.await(pool, ref, 100)
  end