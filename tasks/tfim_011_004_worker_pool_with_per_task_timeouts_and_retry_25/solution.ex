  test "pool_size: 0 starts exactly zero workers" do
    pool =
      start_supervised!(
        {RetryPool,
         pool_size: 0, max_queue: 5, name: :"pool_zero_#{:erlang.unique_integer([:positive])}"},
        id: :zero_pool
      )

    status = RetryPool.status(pool)
    assert status.idle_workers == 0
    assert status.busy_workers == 0

    # With no workers the task can only queue — it must never run.
    {:ok, ref} = RetryPool.submit(pool, quick_task(:never))
    assert {:error, :timeout} = RetryPool.await(pool, ref, 150)
    assert RetryPool.status(pool).queue_length == 1
  end