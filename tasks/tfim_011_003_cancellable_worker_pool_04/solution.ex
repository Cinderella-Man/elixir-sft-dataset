  test "cancel a pending task removes it from queue", %{pool: pool} do
    gate = self()

    # Block both workers
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a task
    {:ok, ref_pending} = CancellablePool.submit(pool, quick_task(:should_cancel))

    # Cancel it
    assert :ok = CancellablePool.cancel(pool, ref_pending)

    # Awaiter gets :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_pending, 1_000)

    # Queue should now be empty
    status = CancellablePool.status(pool)
    assert status.queue_length == 0

    release(w1)
    release(w2)
  end