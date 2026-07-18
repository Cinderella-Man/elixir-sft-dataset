  test "an aged normal task outranks a high task queued after its promotion", %{pool: pool} do
    collector = self()
    gate = self()

    # Occupy both workers so nothing dispatches straight from the queue.
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # This normal task blocks once running, so a single freed worker runs
    # exactly one queued task and no more.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :aged_normal, self()})

          receive do
            :proceed -> :aged_normal
          end
        end,
        :normal
      )

    # Age it past the 500ms promotion interval while both workers stay busy, so
    # the normal → high promotion fires without the task ever executing.
    refute_receive {:executed, :aged_normal, _}, 900

    # Submitted after the promotion tick, so it enters the high queue strictly
    # behind the aged task (which should now be high too).
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_high})
          :fresh_high
        end,
        :high
      )

    # Free exactly one worker: it must pick the aged, promoted-to-high task over
    # the newer high one. A solution that left the task at :normal would run
    # :fresh_high first here instead.
    release(w1)

    assert_receive {:executed, :aged_normal, aged_worker}, 1_000
    refute_receive {:executed, :fresh_high}, 300

    release(aged_worker)
    release(w2)
  end