  test "cancelling a running task increments cancelled_count", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, blocking_task(self()))
    assert_receive {:ready, _w}, 1_000

    assert :ok = CancellablePool.cancel(pool, ref)
    assert {:error, :cancelled} = CancellablePool.await(pool, ref, 1_000)

    assert CancellablePool.status(pool).cancelled_count == 1
  end