  test "within same priority, tasks are FIFO", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue three normal tasks
    for i <- 1..3 do
      PriorityWorkerPool.submit(
        pool,
        fn ->
          send(collector, {:executed, i})
          i
        end,
        :normal
      )
    end

    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    assert_receive {:executed, 3}, 1_000
  end