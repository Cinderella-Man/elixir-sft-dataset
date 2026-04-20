defmodule ConcurrentPriorityQueueTest do
  use ExUnit.Case, async: false

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  setup do
    {:ok, pid} =
      ConcurrentPriorityQueue.start_link(
        processor: recording_processor(),
        max_concurrency: 1
      )

    %{pq: pid}
  end

  # -------------------------------------------------------
  # Basic enqueue / process (concurrency=1)
  # -------------------------------------------------------

  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ConcurrentPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ConcurrentPriorityQueue.processed(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order with concurrency=1", %{pq: pq} do
    ConcurrentPriorityQueue.enqueue(pq, "first", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "second", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "third", :normal)

    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "critical > normal > low priority ordering", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 1
      )

    # Occupy the single slot
    ConcurrentPriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ConcurrentPriorityQueue.enqueue(pq2, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_a", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_b", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_b", :critical)

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    tasks = ConcurrentPriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "critical_a",
             "critical_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end

  # -------------------------------------------------------
  # Concurrency > 1
  # -------------------------------------------------------

  test "processes multiple tasks concurrently up to max_concurrency" do
    # Use an Agent to track the high-water mark of concurrent workers
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          # Increment active count
          Agent.update(hwm_agent, fn {current, max} ->
            new = current + 1
            {new, max(max, new)}
          end)

          Process.sleep(50)

          # Decrement active count
          Agent.update(hwm_agent, fn {current, max} -> {current - 1, max} end)

          {:processed, task}
        end,
        max_concurrency: 3
      )

    for i <- 1..9 do
      ConcurrentPriorityQueue.enqueue(pq, "task_#{i}", :normal)
    end

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)

    # The high-water mark should be exactly 3 (our max_concurrency)
    assert high_water_mark == 3

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 9

    Agent.stop(hwm_agent)
  end

  test "never exceeds max_concurrency even under burst enqueue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(20)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 5
      )

    # Burst enqueue 25 tasks from multiple processes
    1..25
    |> Enum.map(fn i ->
      Task.async(fn ->
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        ConcurrentPriorityQueue.enqueue(pq, i, priority)
      end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark <= 5

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 25

    Agent.stop(hwm_agent)
  end

  test "concurrency=1 behaves like a sequential queue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(10)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 1
      )

    for i <- 1..5 do
      ConcurrentPriorityQueue.enqueue(pq, i, :normal)
    end

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark == 1

    Agent.stop(hwm_agent)
  end

  # -------------------------------------------------------
  # Priority with concurrency > 1
  # -------------------------------------------------------

  test "with concurrency > 1, higher priority tasks still get slots first" do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 2
      )

    # Fill both slots with blockers
    ConcurrentPriorityQueue.enqueue(pq, "blocker_1", :low)
    ConcurrentPriorityQueue.enqueue(pq, "blocker_2", :low)
    Process.sleep(10)

    # Queue up mixed priorities
    ConcurrentPriorityQueue.enqueue(pq, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq, "normal_a", :normal)

    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 2
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 1

    # Release all blockers
    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # Blockers finish first (in some order), then critical, normal, low
    # With concurrency=2, the two blockers finish ~simultaneously,
    # then critical_a and normal_a start together, then low_a
    blocker_tasks = Enum.take(tasks, 2) |> Enum.sort()
    assert blocker_tasks == ["blocker_1", "blocker_2"]

    remaining = Enum.drop(tasks, 2)
    # critical_a should appear before low_a in the remaining
    critical_idx = Enum.find_index(remaining, &(&1 == "critical_a"))
    low_idx = Enum.find_index(remaining, &(&1 == "low_a"))
    assert critical_idx < low_idx
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports accurate counts", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 2
      )

    # Fill both slots
    ConcurrentPriorityQueue.enqueue(pq2, "active_1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "active_2", :normal)
    Process.sleep(10)

    # Queue pending tasks
    ConcurrentPriorityQueue.enqueue(pq2, "c1", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "n1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "l1", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "l2", :low)

    status = ConcurrentPriorityQueue.status(pq2)
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 2
    assert status.active == 2
    assert status.max_concurrency == 2

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    final_status = ConcurrentPriorityQueue.status(pq2)
    assert final_status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 2}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros", %{pq: pq} do
    status = ConcurrentPriorityQueue.status(pq)
    assert status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 1}
  end

  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert ConcurrentPriorityQueue.processed(pq) == []
  end

  test "start_link rejects non-positive max_concurrency" do
    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: -1)
    end
  end

  # -------------------------------------------------------
  # Processor function
  # -------------------------------------------------------

  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        max_concurrency: 1
      )

    ConcurrentPriorityQueue.enqueue(pq2, 5, :normal)
    ConcurrentPriorityQueue.enqueue(pq2, 10, :critical)
    ConcurrentPriorityQueue.drain(pq2)

    result_map = Map.new(ConcurrentPriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Drain waits for active workers too
  # -------------------------------------------------------

  test "drain blocks until active workers finish, not just until queue is empty" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(100)
          {:processed, task}
        end,
        max_concurrency: 3
      )

    ConcurrentPriorityQueue.enqueue(pq, "a", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "b", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "c", :normal)

    # Queue is drained quickly (all 3 start immediately), but workers take 100ms
    ConcurrentPriorityQueue.drain(pq)

    # If drain returned, all workers must be finished
    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 3
    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 0
  end

  # -------------------------------------------------------
  # Stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues with high concurrency" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        max_concurrency: 10
      )

    tasks =
      for i <- 1..100 do
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ConcurrentPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 100

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..100)
  end
end
