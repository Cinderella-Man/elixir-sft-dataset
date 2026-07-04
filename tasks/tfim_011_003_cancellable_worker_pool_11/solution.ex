  test "cancelled_count increments on each cancellation", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:c1))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:c2))

    CancellablePool.cancel(pool, r1)
    CancellablePool.cancel(pool, r2)

    status = CancellablePool.status(pool)
    assert status.cancelled_count == 2

    release(w1)
    release(w2)
  end