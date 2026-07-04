  test "cancel a running task kills the worker and notifies awaiter", %{pool: pool} do
    gate = self()

    {:ok, ref_running} = CancellablePool.submit(pool, blocking_task(gate))
    assert_receive {:ready, _w1}, 1_000

    # Cancel the running task
    assert :ok = CancellablePool.cancel(pool, ref_running)

    # Awaiter receives :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_running, 1_000)
  end