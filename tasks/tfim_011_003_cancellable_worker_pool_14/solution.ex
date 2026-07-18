  test "crash during task returns task_crashed to awaiter", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, fn -> raise "boom" end)
    assert {:error, {:task_crashed, _reason}} = CancellablePool.await(pool, ref, 2_000)
  end