  test "max_retries of 0 is the default — no retries", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "once" end)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end