  test "task timeout triggers retry when retries remain", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # First attempt times out, second attempt succeeds quickly
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn ->
          count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

          if count == 0 do
            # First attempt: sleep longer than timeout
            Process.sleep(5_000)
            :too_slow
          else
            :fast_enough
          end
        end,
        task_timeout: 200,
        max_retries: 1
      )

    assert {:ok, :fast_enough} = RetryPool.await(pool, ref, 5_000)
    Agent.stop(counter)
  end