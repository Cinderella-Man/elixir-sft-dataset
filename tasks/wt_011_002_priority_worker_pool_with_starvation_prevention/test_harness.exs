defmodule PriorityWorkerPoolTest do
  use ExUnit.Case, async: false

  defp quick_task(value) do
    fn -> value end
  end

  defp slow_task(ms, value) do
    fn ->
      Process.sleep(ms)
      value
    end
  end

  defp blocking_task(gate) do
    fn ->
      send(gate, {:ready, self()})

      receive do
        :proceed -> :done
      end
    end
  end

  defp release(worker_pid) do
    send(worker_pid, :proceed)
  end

  setup do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 2,
         max_queue: 5,
         promote_after_ms: 500,
         name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await
  # -------------------------------------------------------

  test "submit and await a simple task at default priority", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(42))
    assert {:ok, 42} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

  test "submit and await tasks at different priorities", %{pool: pool} do
    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:hi), :high)
    {:ok, r2} = PriorityWorkerPool.submit(pool, quick_task(:lo), :low)
    {:ok, r3} = PriorityWorkerPool.submit(pool, quick_task(:mid), :normal)

    assert {:ok, :hi} = PriorityWorkerPool.await(pool, r1, 1_000)
    assert {:ok, :lo} = PriorityWorkerPool.await(pool, r2, 1_000)
    assert {:ok, :mid} = PriorityWorkerPool.await(pool, r3, 1_000)
  end

  test "return value of the task function is the await result", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> %{key: "value"} end, :high)
    assert {:ok, %{key: "value"}} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

  # -------------------------------------------------------
  # Priority ordering
  # -------------------------------------------------------

  test "high-priority queued tasks execute before normal and low", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue tasks in reverse priority order
    {:ok, _} = PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, :low}); :low end, :low)
    {:ok, _} = PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, :normal}); :normal end, :normal)
    {:ok, _} = PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, :high}); :high end, :high)

    # Release one worker at a time
    release(w1)
    assert_receive {:executed, :high}, 1_000

    release(w2)
    assert_receive {:executed, :normal}, 1_000

    # Third task runs on whichever finishes first
    assert_receive {:executed, :low}, 1_000
  end

  test "within same priority, tasks are FIFO", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue three normal tasks
    for i <- 1..3 do
      PriorityWorkerPool.submit(pool, fn -> send(collector, {:executed, i}); i end, :normal)
    end

    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    assert_receive {:executed, 3}, 1_000
  end

  # -------------------------------------------------------
  # Queue behavior
  # -------------------------------------------------------

  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = PriorityWorkerPool.submit(pool, quick_task(:queued_1), :normal)
    {:ok, r4} = PriorityWorkerPool.submit(pool, quick_task(:queued_2), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.busy_workers == 2
    assert status.idle_workers == 0
    assert status.total_queue_length >= 2

    release(w1)
    release(w2)

    assert {:ok, :queued_1} = PriorityWorkerPool.await(pool, r3, 2_000)
    assert {:ok, :queued_2} = PriorityWorkerPool.await(pool, r4, 2_000)
  end

  test "queue rejects when full across all priorities", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 5)
    for _ <- 1..5 do
      {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:filler), :normal)
    end

    # All priorities should be rejected when queue is full
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :high)
    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:overflow), :low)

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Status introspection
  # -------------------------------------------------------

  test "status reflects pool state accurately", %{pool: pool} do
    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_high == 0
    assert status.queue_normal == 0
    assert status.queue_low == 0
    assert status.total_queue_length == 0
  end

  test "status shows per-priority queue counts", %{pool: pool} do
    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:h1), :high)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:n1), :normal)
    {:ok, _} = PriorityWorkerPool.submit(pool, quick_task(:l1), :low)

    status = PriorityWorkerPool.status(pool)
    assert status.queue_high == 1
    assert status.queue_normal == 1
    assert status.queue_low == 1
    assert status.total_queue_length == 3

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Timeout
  # -------------------------------------------------------

  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, slow_task(2_000, :late), :normal)
    assert {:error, :timeout} = PriorityWorkerPool.await(pool, ref, 100)
  end

  # -------------------------------------------------------
  # Starvation prevention
  # -------------------------------------------------------

  test "low-priority tasks are promoted after waiting too long", %{pool: pool} do
    collector = self()
    gate = self()

    # Block both workers
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a low-priority task
    {:ok, _} = PriorityWorkerPool.submit(pool, fn ->
      send(collector, {:executed, :promoted_low})
      :promoted_low
    end, :low)

    # Wait for promotion (promote_after_ms is 500ms in setup)
    Process.sleep(700)

    # Now enqueue a normal-priority task AFTER promotion should have occurred
    {:ok, _} = PriorityWorkerPool.submit(pool, fn ->
      send(collector, {:executed, :fresh_normal})
      :fresh_normal
    end, :normal)

    # The promoted task (was :low, now :normal or :high) should be in front of
    # or at same level as the fresh normal task
    # Release one worker — the promoted task should run first (it was promoted AND is older)
    release(w1)
    assert_receive {:executed, :promoted_low}, 1_000

    release(w2)
    assert_receive {:executed, :fresh_normal}, 1_000
  end

  # -------------------------------------------------------
  # Worker crash recovery
  # -------------------------------------------------------

  test "crash during task returns error to awaiter", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "boom" end, :high)
    assert {:error, {:task_crashed, _reason}} = PriorityWorkerPool.await(pool, ref, 2_000)
  end

  test "pool remains functional after a worker crash", %{pool: pool} do
    {:ok, ref_crash} = PriorityWorkerPool.submit(pool, fn -> raise "kaboom" end)
    PriorityWorkerPool.await(pool, ref_crash, 2_000)

    Process.sleep(100)

    {:ok, ref} = PriorityWorkerPool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = PriorityWorkerPool.await(pool, ref, 1_000)
  end

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

  test "worker count is restored after crash", %{pool: pool} do
    {:ok, ref} = PriorityWorkerPool.submit(pool, fn -> raise "die" end)
    PriorityWorkerPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 2, promote_after_ms: 60_000,
         name: :single_priority_pool},
        id: :single
      )

    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:only), :low)
    assert {:ok, :only} = PriorityWorkerPool.await(pool, r1, 1_000)
  end

  test "max_queue of 0 means no queuing", _context do
    pool =
      start_supervised!(
        {PriorityWorkerPool,
         pool_size: 1, max_queue: 0, promote_after_ms: 60_000,
         name: :no_queue_priority_pool},
        id: :no_queue
      )

    gate = self()

    {:ok, _} = PriorityWorkerPool.submit(pool, blocking_task(gate))
    assert_receive {:ready, w1}, 1_000

    assert {:error, :queue_full} = PriorityWorkerPool.submit(pool, quick_task(:nope), :high)

    release(w1)
  end

  test "await with an unknown ref times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = PriorityWorkerPool.await(pool, bogus_ref, 200)
  end
end
