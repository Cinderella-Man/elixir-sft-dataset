  test "retry_count in status increments with each retry", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 2, :ok),
        max_retries: 3
      )

    assert {:ok, :ok} = RetryPool.await(pool, ref, 5_000)

    Process.sleep(100)

    status = RetryPool.status(pool)
    # Failed twice → 2 retries
    assert status.retry_count == 2
    Agent.stop(counter)
  end