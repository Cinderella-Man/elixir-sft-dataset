  test "worker count is restored after crashes", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "die" end, max_retries: 0)
    RetryPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = RetryPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end