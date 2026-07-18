  test "processed follows completion order rather than start order at concurrency 3" do
    test_pid = self()

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          send(test_pid, {:started, task, self()})

          receive do
            :go -> :ok
          end

          {:done, task}
        end,
        max_concurrency: 3
      )

    for t <- ["a", "b", "c"] do
      assert :ok = ConcurrentPriorityQueue.enqueue(pq, t, :normal)
    end

    workers =
      for _ <- 1..3, into: %{} do
        assert_receive {:started, task, worker}, 1000
        {task, worker}
      end

    for t <- ["c", "a", "b"] do
      worker = Map.fetch!(workers, t)
      ref = Process.monitor(worker)
      send(worker, :go)
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    end

    assert :ok = ConcurrentPriorityQueue.drain(pq)

    finished = Enum.map(ConcurrentPriorityQueue.processed(pq), &elem(&1, 0))
    assert finished == ["c", "a", "b"]
  end