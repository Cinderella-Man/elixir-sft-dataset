  test "task timeout exhausting all retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :never),
        task_timeout: 100, max_retries: 1
      )

    assert {:error, {:task_timeout, 2}} = RetryPool.await(pool, ref, 5_000)
  end