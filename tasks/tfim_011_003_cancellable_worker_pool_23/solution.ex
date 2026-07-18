  test "cancelling a queued task prevents that task from ever executing", %{pool: pool} do
    gate = self()
    me = self()

    # Occupy both workers so the next submission is queued, not dispatched.
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a task with an observable side effect, then cancel it while queued.
    {:ok, ref} =
      CancellablePool.submit(pool, fn ->
        send(me, :sneaky_ran)
        :sneaky
      end)

    assert :ok = CancellablePool.cancel(pool, ref)

    # Free both workers so the queue would drain if the task were still present.
    release(w1)
    release(w2)

    # A fresh task proves the pool has cycled through a dispatch pass.
    {:ok, probe} = CancellablePool.submit(pool, quick_task(:probe))
    assert {:ok, :probe} = CancellablePool.await(pool, probe, 1_000)

    # The cancelled task must never have run.
    refute_receive :sneaky_ran, 300
  end