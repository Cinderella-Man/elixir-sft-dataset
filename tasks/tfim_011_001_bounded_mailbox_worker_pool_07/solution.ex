  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    # Block the single-ish pool — use pool_size: 1 for clearer ordering
    # We'll use the 2-worker pool but block both workers first
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue tasks that report their execution order
    for i <- 1..3 do
      WorkerPool.submit(pool, fn ->
        send(collector, {:executed, i})
        i
      end)
    end

    # Release one worker at a time to force serial execution
    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    # Third task runs on whichever worker finishes first
    assert_receive {:executed, 3}, 1_000
  end