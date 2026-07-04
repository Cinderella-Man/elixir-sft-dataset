  test "crash during task returns error to awaiter", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, fn -> raise "boom" end)

    assert {:error, {:task_crashed, _reason}} = WorkerPool.await(pool, ref, 2_000)
  end