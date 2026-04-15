defmodule PriorityQueueTest do
  use ExUnit.Case, async: false

  # A processor that records what it processed and simulates a tiny delay
  # so we can reason about ordering deterministically.
  defp recording_processor do
    fn task ->
      # Small sleep to make sure messages are queued before being consumed
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      PriorityQueue.start_link(processor: recording_processor())

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = PriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = PriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = PriorityQueue.processed(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    PriorityQueue.enqueue(pq, "first", :normal)
    PriorityQueue.enqueue(pq, "second", :normal)
    PriorityQueue.enqueue(pq, "third", :normal)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high priority tasks are processed before normal and low", %{pq: pq} do
    # Enqueue a low-priority task first so the processor picks it up
    # and is busy while we enqueue the rest.
    PriorityQueue.enqueue(pq, "low_1", :low)

    # Give processor a moment to start on low_1
    Process.sleep(2)

    # Now enqueue mixed priorities while processor is busy
    PriorityQueue.enqueue(pq, "low_2", :low)
    PriorityQueue.enqueue(pq, "normal_1", :normal)
    PriorityQueue.enqueue(pq, "high_1", :high)
    PriorityQueue.enqueue(pq, "normal_2", :normal)
    PriorityQueue.enqueue(pq, "high_2", :high)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # low_1 was already being processed, so it comes first.
    # After that: high_1, high_2 (high FIFO), normal_1, normal_2 (normal FIFO), low_2
    assert tasks == ["low_1", "high_1", "high_2", "normal_1", "normal_2", "low_2"]
  end

  test "high beats normal beats low in a clean queue", %{pq: _pq} do
    # Use a processor with a gate so nothing starts until we've enqueued everything
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          # Block until gate process is dead (will be killed below)
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Enqueue one task to occupy the processor at the gate
    PriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    PriorityQueue.enqueue(pq2, "low_a", :low)
    PriorityQueue.enqueue(pq2, "low_b", :low)
    PriorityQueue.enqueue(pq2, "normal_a", :normal)
    PriorityQueue.enqueue(pq2, "normal_b", :normal)
    PriorityQueue.enqueue(pq2, "high_a", :high)
    PriorityQueue.enqueue(pq2, "high_b", :high)

    # Release the gate — all queued tasks will now be processed in priority order
    Process.exit(gate, :kill)

    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # blocker was already running, then strict priority order
    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a",
             "low_b"
           ]
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts accurately", %{pq: _pq} do
    # Use a gated processor so tasks pile up
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Enqueue one to occupy the processor
    PriorityQueue.enqueue(pq2, "blocker", :normal)
    Process.sleep(10)

    # These will all be pending
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)
    PriorityQueue.enqueue(pq2, "l3", :low)

    status = PriorityQueue.status(pq2)
    assert status.high == 2
    assert status.normal == 1
    assert status.low == 3

    # Release and let everything finish
    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    status_after = PriorityQueue.status(pq2)
    assert status_after == %{high: 0, normal: 0, low: 0}
  end

  # -------------------------------------------------------
  # FIFO within priority
  # -------------------------------------------------------

  test "FIFO is maintained within each priority level", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    PriorityQueue.enqueue(pq2, "l_blocker", :low)
    Process.sleep(10)

    # Enqueue several tasks per level
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "n2", :normal)
    PriorityQueue.enqueue(pq2, "n3", :normal)
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # Extract subsequences per priority
    high_tasks = Enum.filter(tasks, &String.starts_with?(&1, "h"))
    normal_tasks = Enum.filter(tasks, &String.starts_with?(&1, "n"))
    low_tasks = Enum.filter(tasks, &String.starts_with?(&1, "l"))

    assert high_tasks == ["h1", "h2"]
    assert normal_tasks == ["n1", "n2", "n3"]
    assert low_tasks == ["l_blocker", "l1", "l2"]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = PriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    assert PriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0}
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert PriorityQueue.processed(pq) == []
  end

  test "enqueue with all three priorities in reverse order", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    PriorityQueue.enqueue(pq2, "blocker", :high)
    Process.sleep(10)

    PriorityQueue.enqueue(pq2, "low_only", :low)
    PriorityQueue.enqueue(pq2, "normal_only", :normal)
    PriorityQueue.enqueue(pq2, "high_only", :high)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "high_only", "normal_only", "low_only"]
  end

  # -------------------------------------------------------
  # Processor function receives the task value
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(processor: fn n -> n * 2 end)

    PriorityQueue.enqueue(pq2, 5, :normal)
    PriorityQueue.enqueue(pq2, 10, :high)
    PriorityQueue.drain(pq2)

    results = PriorityQueue.processed(pq2)

    # high comes first if it was queued before processing started,
    # but with fast processing, ordering may vary.
    # Just check both tasks were processed with correct results.
    assert {5, 10} in results or {10, 20} in results
    result_map = Map.new(results)
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent enqueue stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    # Enqueue from multiple processes concurrently
    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> PriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    PriorityQueue.drain(pq2)

    processed = PriorityQueue.processed(pq2)
    assert length(processed) == 50

    # Verify all tasks were processed (order may vary due to concurrent enqueue)
    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end
end
