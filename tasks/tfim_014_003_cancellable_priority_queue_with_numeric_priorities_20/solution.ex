  test "cancel on the task currently being processed returns not_found" do
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

    {:ok, ref} = CancellablePriorityQueue.enqueue(pq2, "in_flight", 0)

    assert_receive {:started, "in_flight", worker}, 1_000
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq2, ref)

    send(worker, :release)
    assert :ok = CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["in_flight"]
  end