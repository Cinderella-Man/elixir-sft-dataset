  test "cancelling a running task frees a worker for queued work", %{pool: pool} do
    gate = self()

    # Fill both workers
    {:ok, ref_to_cancel} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, _w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue a task
    {:ok, ref_queued} = CancellablePool.submit(pool, quick_task(:from_queue))

    # Cancel the first running task — replacement should grab queued task
    assert :ok = CancellablePool.cancel(pool, ref_to_cancel)

    # The queued task should complete on the replacement worker
    assert {:ok, :from_queue} = CancellablePool.await(pool, ref_queued, 2_000)

    release(w2)
  end