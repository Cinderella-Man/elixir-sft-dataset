  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, slow_task(2_000, :late), :normal)
    assert {:error, :timeout} = PriorityWorkerPool.await(pool, ref, 100)
  end