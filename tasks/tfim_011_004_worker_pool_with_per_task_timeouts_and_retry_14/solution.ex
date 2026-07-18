  test "pool remains functional after crashes and retries", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(pool, flaky_task(counter, 100, :never), max_retries: 2)

    RetryPool.await(pool, ref, 5_000)
    Process.sleep(200)

    {:ok, ref2} = RetryPool.submit(pool, quick_task(:after_retries))
    assert {:ok, :after_retries} = RetryPool.await(pool, ref2, 1_000)
    Agent.stop(counter)
  end