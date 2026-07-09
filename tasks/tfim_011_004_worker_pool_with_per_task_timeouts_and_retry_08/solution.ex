  test "task that exceeds its timeout with no retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :too_slow),
        task_timeout: 200,
        max_retries: 0
      )

    assert {:error, {:task_timeout, 1}} = RetryPool.await(pool, ref, 3_000)
  end