  test "submitting many tasks beyond pool+queue capacity", %{pool: pool} do
    gate = self()

    # Block both workers
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill queue (3 slots)
    results =
      for i <- 1..5 do
        WorkerPool.submit(pool, quick_task(i))
      end

    ok_count = Enum.count(results, &match?({:ok, _}, &1))
    err_count = Enum.count(results, &match?({:error, :queue_full}, &1))

    assert ok_count == 3
    assert err_count == 2

    release(w1)
    release(w2)
  end