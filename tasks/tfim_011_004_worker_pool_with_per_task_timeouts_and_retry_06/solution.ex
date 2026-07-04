  test "task that exhausts all retries returns task_failed with attempt count", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 100, :never),
        max_retries: 2
      )

    assert {:error, {:task_failed, _reason, 3}} = RetryPool.await(pool, ref, 5_000)

    # 1 initial + 2 retries = 3 total
    assert Agent.get(counter, & &1) == 3
    Agent.stop(counter)
  end