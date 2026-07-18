  test "queued tasks are not lost when a worker crashes", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    {:ok, ref_crash} =
      PriorityWorkerPool.submit(pool, fn ->
        Process.sleep(50)
        raise "crash"
      end)

    {:ok, ref_after} = PriorityWorkerPool.submit(pool, quick_task(:survived), :high)

    assert {:error, {:task_crashed, _}} = PriorityWorkerPool.await(pool, ref_crash, 2_000)

    Process.sleep(200)

    assert {:ok, :survived} = PriorityWorkerPool.await(pool, ref_after, 2_000)

    release(w1)
  end