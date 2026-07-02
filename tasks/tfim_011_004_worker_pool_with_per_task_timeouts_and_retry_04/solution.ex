  test "crash with no retries returns task_failed immediately", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "boom" end, max_retries: 0)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end