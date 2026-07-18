  test "queue rejects when full", %{pool: pool} do
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for _ <- 1..5 do
      {:ok, _} = RetryPool.submit(pool, quick_task(:filler))
    end

    assert {:error, :queue_full} = RetryPool.submit(pool, quick_task(:overflow))

    release(w1)
    release(w2)
  end