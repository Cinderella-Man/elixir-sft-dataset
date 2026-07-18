  test "an aged low task is dispatched before a normal task queued after the promotion",
       %{pool: pool} do
    collector = self()
    gate = self()

    # Occupy both workers so nothing can be dispatched from the queue.
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # This low task blocks once it starts, so a single freed worker can run
    # exactly one queued task and no more.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :aged_low, self()})

          receive do
            :proceed -> :aged_low
          end
        end,
        :low
      )

    # Both workers stay busy while the 500ms promotion interval from setup
    # elapses, so the low task ages in the queue without executing.
    refute_receive {:executed, :aged_low, _}, 900

    # Submitted after the promotion tick, so it is strictly newer than the
    # aged task and sits behind it at the same (promoted) priority level.
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_normal})
          :fresh_normal
        end,
        :normal
      )

    # Free exactly one worker: it must choose the aged, promoted task over the
    # newer normal one. The other worker stays blocked, so a solution that
    # still ranks the task as :low would run :fresh_normal here instead.
    release(w1)

    assert_receive {:executed, :aged_low, aged_worker}, 1_000
    refute_receive {:executed, :fresh_normal}, 300

    release(aged_worker)
    release(w2)
  end