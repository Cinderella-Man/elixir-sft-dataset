  test "double cancel returns not_found on second attempt", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, ref} = CancellablePool.submit(pool, quick_task(:target))

    assert :ok = CancellablePool.cancel(pool, ref)
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)

    release(w1)
    release(w2)
  end