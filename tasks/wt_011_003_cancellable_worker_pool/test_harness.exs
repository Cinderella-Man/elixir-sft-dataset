defmodule CancellablePoolTest do
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
        {CancellablePool,
         pool_size: 2, max_queue: 3, name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await
  # -------------------------------------------------------

  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(42))
    assert {:ok, 42} = CancellablePool.await(pool, ref, 1_000)
  end

  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = CancellablePool.submit(pool, quick_task(:a))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:b))
    {:ok, r3} = CancellablePool.submit(pool, quick_task(:c))

    assert {:ok, :a} = CancellablePool.await(pool, r1, 1_000)
    assert {:ok, :b} = CancellablePool.await(pool, r2, 1_000)
    assert {:ok, :c} = CancellablePool.await(pool, r3, 1_000)
  end

  # -------------------------------------------------------
  # Cancel a pending (queued) task
  # -------------------------------------------------------

  test "cancel a pending task removes it from queue", %{pool: pool} do
    gate = self()

    # Block both workers
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Enqueue a task
    {:ok, ref_pending} = CancellablePool.submit(pool, quick_task(:should_cancel))

    # Cancel it
    assert :ok = CancellablePool.cancel(pool, ref_pending)

    # Awaiter gets :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_pending, 1_000)

    # Queue should now be empty
    status = CancellablePool.status(pool)
    assert status.queue_length == 0

    release(w1)
    release(w2)
  end

  test "cancelling a pending task frees a queue slot", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Fill the queue (max_queue: 3)
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, ref_q3} = CancellablePool.submit(pool, quick_task(:q3))

    # Queue is full
    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    # Cancel one queued task
    assert :ok = CancellablePool.cancel(pool, ref_q3)

    # Now there's room
    {:ok, _} = CancellablePool.submit(pool, quick_task(:fits_now))

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Cancel a running task
  # -------------------------------------------------------

  test "cancel a running task kills the worker and notifies awaiter", %{pool: pool} do
    gate = self()

    {:ok, ref_running} = CancellablePool.submit(pool, blocking_task(gate))
    assert_receive {:ready, _w1}, 1_000

    # Cancel the running task
    assert :ok = CancellablePool.cancel(pool, ref_running)

    # Awaiter receives :cancelled
    assert {:error, :cancelled} = CancellablePool.await(pool, ref_running, 1_000)
  end

  test "after cancelling a running task, replacement worker picks up queued work", %{pool: pool} do
    gate = self()

    # Fill both workers
    {:ok, ref_to_cancel} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, _w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    # Queue a task
    {:ok, ref_queued} = CancellablePool.submit(pool, quick_task(:from_queue))

    # Cancel the first running task — replacement should grab queued task
    assert :ok = CancellablePool.cancel(pool, ref_to_cancel)

    # The queued task should complete on the replacement worker
    assert {:ok, :from_queue} = CancellablePool.await(pool, ref_queued, 2_000)

    release(w2)
  end

  # -------------------------------------------------------
  # Cancel unknown ref
  # -------------------------------------------------------

  test "cancel an unknown ref returns not_found", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, :not_found} = CancellablePool.cancel(pool, bogus_ref)
  end

  test "cancel an already-completed task returns not_found", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(:done))
    assert {:ok, :done} = CancellablePool.await(pool, ref, 1_000)

    # Try to cancel after completion
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)
  end

  test "double cancel returns not_found on second attempt", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, ref} = CancellablePool.submit(pool, quick_task(:target))

    assert :ok = CancellablePool.cancel(pool, ref)
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Status / cancelled_count
  # -------------------------------------------------------

  test "cancelled_count increments on each cancellation", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:c1))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:c2))

    CancellablePool.cancel(pool, r1)
    CancellablePool.cancel(pool, r2)

    status = CancellablePool.status(pool)
    assert status.cancelled_count == 2

    release(w1)
    release(w2)
  end

  # -------------------------------------------------------
  # Queue behavior (same as original)
  # -------------------------------------------------------

  test "queue rejects when full", %{pool: pool} do
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, _} = CancellablePool.submit(pool, quick_task(:q1))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q2))
    {:ok, _} = CancellablePool.submit(pool, quick_task(:q3))

    assert {:error, :queue_full} = CancellablePool.submit(pool, quick_task(:overflow))

    release(w1)
    release(w2)
  end

  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))
    {:ok, _} = CancellablePool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for i <- 1..3 do
      CancellablePool.submit(pool, fn ->
        send(collector, {:executed, i})
        i
      end)
    end

    release(w1)
    assert_receive {:executed, 1}, 1_000

    release(w2)
    assert_receive {:executed, 2}, 1_000

    assert_receive {:executed, 3}, 1_000
  end

  # -------------------------------------------------------
  # Worker crash recovery (non-cancellation crashes)
  # -------------------------------------------------------

  test "crash during task returns task_crashed to awaiter", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, fn -> raise "boom" end)
    assert {:error, {:task_crashed, _reason}} = CancellablePool.await(pool, ref, 2_000)
  end

  test "pool remains functional after a worker crash", %{pool: pool} do
    {:ok, ref_crash} = CancellablePool.submit(pool, fn -> raise "kaboom" end)
    CancellablePool.await(pool, ref_crash, 2_000)

    Process.sleep(100)

    {:ok, ref} = CancellablePool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = CancellablePool.await(pool, ref, 1_000)
  end

  test "worker count is restored after crash", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, fn -> raise "die" end)
    CancellablePool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = CancellablePool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Timeout
  # -------------------------------------------------------

  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, slow_task(2_000, :late))
    assert {:error, :timeout} = CancellablePool.await(pool, ref, 100)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {CancellablePool, pool_size: 1, max_queue: 2, name: :single_cancel_pool},
        id: :single
      )

    {:ok, r1} = CancellablePool.submit(pool, quick_task(:only))
    assert {:ok, :only} = CancellablePool.await(pool, r1, 1_000)
  end

  test "await with an unknown ref returns timeout", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = CancellablePool.await(pool, bogus_ref, 200)
  end
end
