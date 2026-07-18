  test "queued tasks are not lost when a worker crashes", %{pool: pool} do
    gate = self()

    # Block worker 1 with a normal task
    {:ok, _} = WorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    # Worker 2 gets the crashing task
    {:ok, ref_crash} =
      WorkerPool.submit(pool, fn ->
        Process.sleep(50)
        raise "crash"
      end)

    # Queue a task behind the crash
    {:ok, ref_after} = WorkerPool.submit(pool, quick_task(:survived))

    # The crash task should fail
    assert {:error, {:task_crashed, _}} = WorkerPool.await(pool, ref_crash, 2_000)

    # Give pool time to restart worker and dequeue
    Process.sleep(200)

    # The queued task should still complete
    assert {:ok, :survived} = WorkerPool.await(pool, ref_after, 2_000)

    # Cleanup
    release(w1)
  end