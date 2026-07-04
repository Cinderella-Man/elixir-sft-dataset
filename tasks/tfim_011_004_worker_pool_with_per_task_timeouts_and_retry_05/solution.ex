  test "task that fails once then succeeds with max_retries: 1", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 1, :recovered),
        max_retries: 1
      )

    assert {:ok, :recovered} = RetryPool.await(pool, ref, 3_000)

    # Should have tried twice total
    assert Agent.get(counter, & &1) == 2
    Agent.stop(counter)
  end