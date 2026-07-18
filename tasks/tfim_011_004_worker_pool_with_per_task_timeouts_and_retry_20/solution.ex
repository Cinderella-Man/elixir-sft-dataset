  test "await timeout fires even while task is being retried", %{pool: pool} do
    # Task that always fails, with many retries and a long timeout
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn ->
          Process.sleep(500)
          raise "slow fail"
        end,
        max_retries: 10,
        task_timeout: 30_000
      )

    # Await with a short timeout — should not wait for all retries
    assert {:error, :timeout} = RetryPool.await(pool, ref, 200)
  end