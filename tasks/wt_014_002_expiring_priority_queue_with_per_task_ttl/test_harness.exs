defmodule ExpiringPriorityQueueTest do
  use ExUnit.Case, async: false

  defp start_clock(initial) do
    {:ok, agent} = Agent.start_link(fn -> initial end)
    agent
  end

  defp advance_clock(agent, ms) do
    Agent.update(agent, fn t -> t + ms end)
  end

  defp clock_fn(agent) do
    fn -> Agent.get(agent, & &1) end
  end

  defp recording_processor do
    fn task ->
      Process.sleep(5)
      {:processed, task}
    end
  end

  # -------------------------------------------------------
  # Basic enqueue / process
  # -------------------------------------------------------

  test "processes a single enqueued task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert :ok = ExpiringPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ExpiringPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ExpiringPriorityQueue.processed(pq)
    assert [] = ExpiringPriorityQueue.expired(pq)
  end

  test "processes multiple tasks of the same priority in FIFO order" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    ExpiringPriorityQueue.enqueue(pq, "first", :normal)
    ExpiringPriorityQueue.enqueue(pq, "second", :normal)
    ExpiringPriorityQueue.enqueue(pq, "third", :normal)

    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high priority tasks are processed before normal and low" do
    clock_agent = start_clock(0)

    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ExpiringPriorityQueue.enqueue(pq, "low_a", :low)
    ExpiringPriorityQueue.enqueue(pq, "normal_a", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_a", :high)
    ExpiringPriorityQueue.enqueue(pq, "normal_b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_b", :high)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end

  # -------------------------------------------------------
  # TTL / Expiration
  # -------------------------------------------------------

  test "expired tasks are skipped and recorded" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100
      )

    # Occupy the processor with a blocker that has a long TTL
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue a task with default short TTL — it stays queued
    ExpiringPriorityQueue.enqueue(pq, "will_expire", :normal)

    # Enqueue a task with long TTL
    ExpiringPriorityQueue.enqueue(pq, "still_valid", :normal, ttl_ms: 50_000)

    # Advance clock past default TTL
    advance_clock(clock_agent, 200)

    # Release the gate — blocker finishes, then process_next finds will_expire is expired
    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq)

    assert processed == ["blocker", "still_valid"]
    assert [{"will_expire", :normal}] = expired
  end

  test "per-task TTL overrides default TTL" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 1000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :high, ttl_ms: 100_000)
    Process.sleep(10)

    # Short custom TTL
    ExpiringPriorityQueue.enqueue(pq, "short_ttl", :normal, ttl_ms: 50)
    # Uses default TTL (1000ms)
    ExpiringPriorityQueue.enqueue(pq, "default_ttl", :normal)

    # Advance clock past short TTL but within default TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed_tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired_tasks = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed_tasks == ["blocker", "default_ttl"]
    assert expired_tasks == ["short_ttl"]
  end

  test "multiple expired tasks are skipped in sequence before finding a valid one" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue several tasks with short TTL
    ExpiringPriorityQueue.enqueue(pq, "expire_1", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_2", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_3", :normal)
    # One with long TTL
    ExpiringPriorityQueue.enqueue(pq, "survivor", :low, ttl_ms: 100_000)

    # Advance past short TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed == ["blocker", "survivor"]
    assert expired == ["expire_1", "expire_2", "expire_3"]
  end

  test "expired tasks record their original priority" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "high_expired", :high)
    ExpiringPriorityQueue.enqueue(pq, "low_expired", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    expired = ExpiringPriorityQueue.expired(pq)
    assert {"high_expired", :high} in expired
    assert {"low_expired", :low} in expired
  end

  test "all tasks expired results in empty processed list (except blocker)" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "c", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert processed == ["blocker"]
    assert length(ExpiringPriorityQueue.expired(pq)) == 3
  end

  # -------------------------------------------------------
  # Status reporting
  # -------------------------------------------------------

  test "status reports pending counts excluding expired tasks" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue tasks — some will expire
    ExpiringPriorityQueue.enqueue(pq, "h1", :high, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "h2_short", :high, ttl_ms: 50)
    ExpiringPriorityQueue.enqueue(pq, "n1", :normal, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "l1_short", :low, ttl_ms: 50)

    # Advance clock to expire the short-TTL tasks
    advance_clock(clock_agent, 100)

    status = ExpiringPriorityQueue.status(pq)
    assert status.high == 1
    assert status.normal == 1
    assert status.low == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)
  end

  test "status shows expired count after processing" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    status = ExpiringPriorityQueue.status(pq)
    assert status.expired == 2
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "drain on empty queue returns immediately" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert :ok = ExpiringPriorityQueue.drain(pq)
  end

  test "status on empty queue returns all zeros" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
  end

  test "processed and expired return empty lists when nothing has been enqueued" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.processed(pq) == []
    assert ExpiringPriorityQueue.expired(pq) == []
  end

  # -------------------------------------------------------
  # Processor function receives and transforms
  # -------------------------------------------------------

  test "processor function receives and transforms the task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    ExpiringPriorityQueue.enqueue(pq, 5, :normal)
    ExpiringPriorityQueue.enqueue(pq, 10, :high)
    ExpiringPriorityQueue.drain(pq)

    result_map = Map.new(ExpiringPriorityQueue.processed(pq))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end

  # -------------------------------------------------------
  # Concurrent stress test
  # -------------------------------------------------------

  test "handles many concurrent enqueues without losing non-expired tasks" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 1_000_000
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ExpiringPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end
end
