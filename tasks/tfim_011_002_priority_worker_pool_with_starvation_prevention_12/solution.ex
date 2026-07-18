  test "low-priority tasks are promoted after waiting too long", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a low-priority task
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :promoted_low})
          :promoted_low
        end,
        :low
      )

    # Wait for promotion (promote_after_ms is 500ms in setup)
    Process.sleep(700)

    # Now enqueue a normal-priority task AFTER promotion should have occurred
    {:ok, _} =
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, :fresh_normal})
          :fresh_normal
        end,
        :normal
      )

    # The promoted task (was :low, now :normal or :high) should be in front of
    # or at same level as the fresh normal task
    # Release one worker — the promoted task should run first (it was promoted AND is older)
    release(w1)
    assert_receive {:executed, :promoted_low}, 1_000

    release(w2)
    assert_receive {:executed, :fresh_normal}, 1_000
  end