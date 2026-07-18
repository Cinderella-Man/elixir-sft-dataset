  test "queue rejects when full", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q3))

    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    release(w1)
    release(w2)
  end