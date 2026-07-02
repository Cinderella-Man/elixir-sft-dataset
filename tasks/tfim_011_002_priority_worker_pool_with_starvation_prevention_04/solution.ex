  test "return value of the task function is the await result", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> %{key: "value"} end, :high)
    assert {:ok, %{key: "value"}} = PriorityWorkerPool.await(pool, ref, 1_000)
  end