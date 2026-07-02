  test "return value of the task function is the await result", %{pool: pool} do
    {:ok, ref} = WorkerPool.submit(pool, fn -> %{key: "value", num: 123} end)
    assert {:ok, %{key: "value", num: 123}} = WorkerPool.await(pool, ref, 1_000)
  end