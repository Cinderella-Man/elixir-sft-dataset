  test "crash during task returns error to awaiter", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "boom" end, :high)
    assert {:error, {:task_crashed, _reason}} = PriorityWorkerPool.await(pool, ref, 2_000)
  end