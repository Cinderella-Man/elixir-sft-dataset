defmodule CancellablePriorityQueueTest do
  use ExUnit.Case, async: false

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      CancellablePriorityQueue.start_link(processor: recording_processor())

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert {:ok, _ref} = CancellablePriorityQueue.enqueue(pq, "task_a", 1)
    assert :ok = CancellablePriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = CancellablePriorityQueue.processed(pq)
  end

  test "enqueue returns unique refs", %{pq: pq} do
    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq, "a", 0)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq, "b", 0)
    {:ok, ref3} = CancellablePriorityQueue.enqueue(pq, "c", 1)

    assert ref1 != ref2
    assert ref2 != ref3
    assert ref1 != ref3
  end

  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    CancellablePriorityQueue.enqueue(pq, "first", 5)
    CancellablePriorityQueue.enqueue(pq, "second", 5)
    CancellablePriorityQueue.enqueue(pq, "third", 5)

    CancellablePriorityQueue.drain(pq)

    tasks = CancellablePriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Numeric priority ordering
  # -------------------------------------------------------

  test "lower priority numbers are processed first", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    # Occupy the processor
    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    # Enqueue in reverse priority order
    CancellablePriorityQueue.enqueue(pq2, "pri_10", 10)
    CancellablePriorityQueue.enqueue(pq2, "pri_5", 5)
    CancellablePriorityQueue.enqueue(pq2, "pri_0", 0)
    CancellablePriorityQueue.enqueue(pq2, "pri_1", 1)
    CancellablePriorityQueue.enqueue(pq2, "pri_5b", 5)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == ["blocker", "pri_0", "pri_1", "pri_5", "pri_5b", "pri_10"]
  end

  test "priority 0 is highest", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "low", 100)
    CancellablePriorityQueue.enqueue(pq2, "urgent", 0)
    CancellablePriorityQueue.enqueue(pq2, "medium", 50)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "urgent", "medium", "low"]
  end

  # -------------------------------------------------------
  # Cancellation
  # -------------------------------------------------------

  test "cancel removes a pending task", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref_a} = CancellablePriorityQueue.enqueue(pq2, "will_cancel", 1)
    CancellablePriorityQueue.enqueue(pq2, "will_process", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref_a)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert "will_cancel" not in tasks
    assert "will_process" in tasks
  end

  test "cancel returns error for unknown ref", %{pq: pq} do
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq, make_ref())
  end

  test "cancel returns error for already processed task", %{pq: pq} do
    {:ok, ref} = CancellablePriorityQueue.enqueue(pq, "fast", 0)
    CancellablePriorityQueue.drain(pq)

    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq, ref)
  end

  test "double cancel returns error on second attempt", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref} = CancellablePriorityQueue.enqueue(pq2, "target", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref)
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq2, ref)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  test "cancelled count is tracked in status", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq2, "a", 1)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq2, "b", 2)
    CancellablePriorityQueue.enqueue(pq2, "c", 3)

    CancellablePriorityQueue.cancel(pq2, ref1)
    CancellablePriorityQueue.cancel(pq2, ref2)

    status = CancellablePriorityQueue.status(pq2)
    assert status.cancelled == 2
    assert status.pending == 1

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts by priority", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "a", 0)
    CancellablePriorityQueue.enqueue(pq2, "b", 0)
    CancellablePriorityQueue.enqueue(pq2, "c", 5)
    CancellablePriorityQueue.enqueue(pq2, "d", 10)
    CancellablePriorityQueue.enqueue(pq2, "e", 10)

    status = CancellablePriorityQueue.status(pq2)
    assert status.pending == 5
    assert status.by_priority == %{0 => 2, 5 => 1, 10 => 2}
    assert status.cancelled == 0

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    final_status = CancellablePriorityQueue.status(pq2)
    assert final_status.pending == 0
    assert final_status.by_priority == %{}
  end

  # -------------------------------------------------------
  # Peek
  # -------------------------------------------------------

  test "peek returns the next task without removing it", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "low", 10)
    CancellablePriorityQueue.enqueue(pq2, "high", 1)

    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)
    # Peek again — still there
    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end

  test "peek on empty queue returns :empty", %{pq: pq} do
    assert :empty = CancellablePriorityQueue.peek(pq)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = CancellablePriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    status = CancellablePriorityQueue.status(pq)
    assert status == %{pending: 0, by_priority: %{}, cancelled: 0}
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert CancellablePriorityQueue.processed(pq) == []
  end

  # -------------------------------------------------------
  # Processor function
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(processor: fn n -> n * 2 end)

    CancellablePriorityQueue.enqueue(pq2, 5, 1)
    CancellablePriorityQueue.enqueue(pq2, 10, 0)
    CancellablePriorityQueue.drain(pq2)

    result_map = Map.new(CancellablePriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = rem(i, 10)
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> CancellablePriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    CancellablePriorityQueue.drain(pq2)

    processed = CancellablePriorityQueue.processed(pq2)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end

  # -------------------------------------------------------
  # Cancel + priority interaction
  # -------------------------------------------------------

  test "cancelling highest priority task causes next priority to be processed first", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)
          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end
          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, high_ref} = CancellablePriorityQueue.enqueue(pq2, "high_cancelled", 0)
    CancellablePriorityQueue.enqueue(pq2, "medium", 5)
    CancellablePriorityQueue.enqueue(pq2, "low", 10)

    CancellablePriorityQueue.cancel(pq2, high_ref)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "medium", "low"]
  end
end
