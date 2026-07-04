  test "cancelling a pending task frees a queue slot", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3)
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, ref_q3} = CancellablePool.submit(pool, quick_task(:q3))

    # Queue is full
    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    # Cancel one queued task
    assert :ok = CancellablePool.cancel(pool, ref_q3)

    # Now there's room
    {:ok, _} = CancellablePool.submit(pool, quick_task(:fits_now))

    release(w1)
    release(w2)
  end