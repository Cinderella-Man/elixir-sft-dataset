  test "a priority level whose tasks were all cancelled disappears from by_priority" do
    parent = self()

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          send(parent, {:started, task, self()})

          receive do
            :release -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    assert_receive {:started, "blocker", worker}, 1_000

    {:ok, ref_a} = CancellablePriorityQueue.enqueue(pq2, "a", 3)
    {:ok, ref_b} = CancellablePriorityQueue.enqueue(pq2, "b", 3)
    CancellablePriorityQueue.enqueue(pq2, "c", 7)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref_a)
    assert :ok = CancellablePriorityQueue.cancel(pq2, ref_b)

    status = CancellablePriorityQueue.status(pq2)
    assert status == %{pending: 1, by_priority: %{7 => 1}, cancelled: 2}
    assert {:ok, "c", 7} = CancellablePriorityQueue.peek(pq2)

    send(worker, :release)
    assert_receive {:started, "c", worker_c}, 1_000
    send(worker_c, :release)
    assert :ok = CancellablePriorityQueue.drain(pq2)
  end