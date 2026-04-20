defmodule RetryPoolTest do
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

  # A task that fails N times, then succeeds
  defp flaky_task(counter_agent, fail_count, success_value) do
    fn ->
      count = Agent.get_and_update(counter_agent, fn n -> {n, n + 1} end)

      if count < fail_count do
        raise "attempt #{count + 1} failed"
      else
        success_value
      end
    end
  end

  setup do
    pool =
      start_supervised!(
        {RetryPool,
         pool_size: 2, max_queue: 5, name: :"pool_#{:erlang.unique_integer([:positive])}"}
      )

    %{pool: pool}
  end

  # -------------------------------------------------------
  # Basic submit / await (no retries)
  # -------------------------------------------------------

  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, quick_task(42))
    assert {:ok, 42} = RetryPool.await(pool, ref, 1_000)
  end

  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = RetryPool.submit(pool, quick_task(:a))
    {:ok, r2} = RetryPool.submit(pool, quick_task(:b))
    {:ok, r3} = RetryPool.submit(pool, quick_task(:c))

    assert {:ok, :a} = RetryPool.await(pool, r1, 1_000)
    assert {:ok, :b} = RetryPool.await(pool, r2, 1_000)
    assert {:ok, :c} = RetryPool.await(pool, r3, 1_000)
  end

  # -------------------------------------------------------
  # Crash without retries → immediate failure
  # -------------------------------------------------------

  test "crash with no retries returns task_failed immediately", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "boom" end, max_retries: 0)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end

  # -------------------------------------------------------
  # Retry on crash
  # -------------------------------------------------------

  test "task that fails once then succeeds with max_retries: 1", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 1, :recovered),
        max_retries: 1
      )

    assert {:ok, :recovered} = RetryPool.await(pool, ref, 3_000)

    # Should have tried twice total
    assert Agent.get(counter, & &1) == 2
    Agent.stop(counter)
  end

  test "task that exhausts all retries returns task_failed with attempt count", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 100, :never),
        max_retries: 2
      )

    assert {:error, {:task_failed, _reason, 3}} = RetryPool.await(pool, ref, 5_000)

    # 1 initial + 2 retries = 3 total
    assert Agent.get(counter, & &1) == 3
    Agent.stop(counter)
  end

  test "retry_count in status increments with each retry", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(
        pool,
        flaky_task(counter, 2, :ok),
        max_retries: 3
      )

    assert {:ok, :ok} = RetryPool.await(pool, ref, 5_000)

    Process.sleep(100)

    status = RetryPool.status(pool)
    # Failed twice → 2 retries
    assert status.retry_count == 2
    Agent.stop(counter)
  end

  # -------------------------------------------------------
  # Per-task timeout
  # -------------------------------------------------------

  test "task that exceeds its timeout with no retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :too_slow),
        task_timeout: 200, max_retries: 0
      )

    assert {:error, {:task_timeout, 1}} = RetryPool.await(pool, ref, 3_000)
  end

  test "task timeout triggers retry when retries remain", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # First attempt times out, second attempt succeeds quickly
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn ->
          count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

          if count == 0 do
            # First attempt: sleep longer than timeout
            Process.sleep(5_000)
            :too_slow
          else
            :fast_enough
          end
        end,
        task_timeout: 200, max_retries: 1
      )

    assert {:ok, :fast_enough} = RetryPool.await(pool, ref, 5_000)
    Agent.stop(counter)
  end

  test "task timeout exhausting all retries returns task_timeout", %{pool: pool} do
    {:ok, ref} =
      RetryPool.submit(
        pool,
        slow_task(2_000, :never),
        task_timeout: 100, max_retries: 1
      )

    assert {:error, {:task_timeout, 2}} = RetryPool.await(pool, ref, 5_000)
  end

  # -------------------------------------------------------
  # Queue behavior
  # -------------------------------------------------------

  test "tasks are queued when all workers are busy", %{pool: pool} do
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    {:ok, r3} = RetryPool.submit(pool, quick_task(:queued))

    status = RetryPool.status(pool)
    assert status.queue_length >= 1

    release(w1)
    release(w2)

    assert {:ok, :queued} = RetryPool.await(pool, r3, 2_000)
  end

  test "queue rejects when full", %{pool: pool} do
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for _ <- 1..5 do
      {:ok, _} = RetryPool.submit(pool, quick_task(:filler))
    end

    assert {:error, :queue_full} = RetryPool.submit(pool, quick_task(:overflow))

    release(w1)
    release(w2)
  end

  test "queued tasks execute in FIFO order", %{pool: pool} do
    collector = self()
    gate = self()

    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))
    {:ok, _} = RetryPool.submit(pool, blocking_task(gate))

    assert_receive {:ready, w1}, 1_000
    assert_receive {:ready, w2}, 1_000

    for i <- 1..3 do
      RetryPool.submit(pool, fn ->
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
  # Pool resilience
  # -------------------------------------------------------

  test "pool remains functional after crashes and retries", %{pool: pool} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, ref} =
      RetryPool.submit(pool, flaky_task(counter, 100, :never), max_retries: 2)

    RetryPool.await(pool, ref, 5_000)
    Process.sleep(200)

    {:ok, ref2} = RetryPool.submit(pool, quick_task(:after_retries))
    assert {:ok, :after_retries} = RetryPool.await(pool, ref2, 1_000)
    Agent.stop(counter)
  end

  test "worker count is restored after crashes", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "die" end, max_retries: 0)
    RetryPool.await(pool, ref, 2_000)

    Process.sleep(200)

    status = RetryPool.status(pool)
    assert status.idle_workers + status.busy_workers == 2
  end

  # -------------------------------------------------------
  # Status introspection
  # -------------------------------------------------------

  test "status reflects pool state accurately", %{pool: pool} do
    status = RetryPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_length == 0
    assert status.retry_count == 0
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "pool_size of 1 works correctly", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 2, name: :single_retry_pool},
        id: :single
      )

    {:ok, r1} = RetryPool.submit(pool, quick_task(:only))
    assert {:ok, :only} = RetryPool.await(pool, r1, 1_000)
  end

  test "await with an unknown ref times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = RetryPool.await(pool, bogus_ref, 200)
  end

  test "max_retries of 0 is the default — no retries", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, fn -> raise "once" end)
    assert {:error, {:task_failed, _reason, 1}} = RetryPool.await(pool, ref, 2_000)
  end

  test "await timeout fires even while task is being retried", %{pool: pool} do
    # Task that always fails, with many retries and a long timeout
    {:ok, ref} =
      RetryPool.submit(
        pool,
        fn -> Process.sleep(500); raise "slow fail" end,
        max_retries: 10, task_timeout: 30_000
      )

    # Await with a short timeout — should not wait for all retries
    assert {:error, :timeout} = RetryPool.await(pool, ref, 200)
  end
end
