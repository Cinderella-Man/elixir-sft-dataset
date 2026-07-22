defmodule KeyedPoolTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = KeyedPool.start_link(max_concurrency: 2)
    %{kp: pid}
  end

  # -------------------------------------------------------
  # Basic execution
  # -------------------------------------------------------

  test "executes the function and returns the result", %{kp: kp} do
    assert {:ok, 42} = KeyedPool.execute(kp, :k, fn -> {:ok, 42} end)
  end

  test "wraps plain return values in an ok tuple", %{kp: kp} do
    assert {:ok, "hello"} = KeyedPool.execute(kp, :k, fn -> "hello" end)
  end

  test "passes through {:error, reason} as-is", %{kp: kp} do
    assert {:error, :boom} = KeyedPool.execute(kp, :k, fn -> {:error, :boom} end)
  end

  test "exception is returned as {:error, {:exception, _}}", %{kp: kp} do
    result = KeyedPool.execute(kp, :k, fn -> raise "kaboom" end)
    assert {:error, {:exception, %RuntimeError{message: "kaboom"}}} = result
  end

  # -------------------------------------------------------
  # NOT deduplication — each caller runs its own function
  # -------------------------------------------------------

  test "each caller gets its own result", %{kp: kp} do
    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          KeyedPool.execute(kp, :k, fn ->
            {:ok, i}
          end)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    # Each caller should get a distinct result matching their own i
    values = Enum.map(results, fn {:ok, v} -> v end) |> Enum.sort()
    assert values == [1, 2, 3, 4, 5]
  end

  test "every caller's function is executed", %{kp: kp} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          KeyedPool.execute(kp, :k, fn ->
            Agent.update(counter, &(&1 + 1))
            Process.sleep(50)
            {:ok, :done}
          end)
        end)
      end

    Task.await_many(tasks, 10_000)

    # All 5 functions ran (unlike dedup which would only run 1)
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Concurrency limiting
  # -------------------------------------------------------

  test "limits concurrent executions to max_concurrency" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 2)
    {:ok, peak} = Agent.start_link(fn -> 0 end)
    {:ok, current} = Agent.start_link(fn -> 0 end)

    tasks =
      for _ <- 1..6 do
        Task.async(fn ->
          KeyedPool.execute(kp, :limited, fn ->
            Agent.update(current, &(&1 + 1))
            cur = Agent.get(current, & &1)
            Agent.update(peak, fn p -> max(p, cur) end)
            Process.sleep(100)
            Agent.update(current, &(&1 - 1))
            {:ok, :done}
          end)
        end)
      end

    Task.await_many(tasks, 10_000)

    # Peak concurrency should never exceed 2
    assert Agent.get(peak, & &1) <= 2
  end

  test "queued callers are started as slots free up" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)
    {:ok, order} = Agent.start_link(fn -> [] end)

    tasks =
      for i <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :serial, fn ->
            Agent.update(order, fn list -> list ++ [i] end)
            Process.sleep(50)
            {:ok, i}
          end)
        end)
      end

    # Give them a moment to all register
    Process.sleep(20)

    results = Task.await_many(tasks, 10_000)

    # All should complete
    values = Enum.map(results, fn {:ok, v} -> v end) |> Enum.sort()
    assert values == [1, 2, 3, 4]

    # With max_concurrency: 1, execution is serial — order should be FIFO
    execution_order = Agent.get(order, & &1)
    assert execution_order == Enum.sort(execution_order)
  end

  # -------------------------------------------------------
  # FIFO queue ordering
  # -------------------------------------------------------

  test "queue is strictly FIFO" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)
    {:ok, order} = Agent.start_link(fn -> [] end)

    # First task grabs the slot and holds it
    blocker =
      Task.async(fn ->
        KeyedPool.execute(kp, :fifo, fn ->
          Process.sleep(300)
          Agent.update(order, fn list -> list ++ [:blocker] end)
          {:ok, :blocker}
        end)
      end)

    Process.sleep(30)

    # Queue up callers in known order
    queued =
      for label <- [:first, :second, :third] do
        Task.async(fn ->
          KeyedPool.execute(kp, :fifo, fn ->
            Agent.update(order, fn list -> list ++ [label] end)
            Process.sleep(20)
            {:ok, label}
          end)
        end)
      end

    Task.await(blocker, 5_000)
    Task.await_many(queued, 5_000)

    assert Agent.get(order, & &1) == [:blocker, :first, :second, :third]
  end

  # -------------------------------------------------------
  # Independent keys
  # -------------------------------------------------------

  test "different keys have independent pools" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)

    tasks =
      for key <- [:a, :b, :c] do
        Task.async(fn ->
          KeyedPool.execute(kp, key, fn ->
            Process.sleep(100)
            {:ok, key}
          end)
        end)
      end

    {elapsed, results} =
      :timer.tc(fn ->
        Task.await_many(tasks, 5_000)
      end)

    assert {:ok, :a} in results
    assert {:ok, :b} in results
    assert {:ok, :c} in results

    # With 3 independent keys at max_concurrency: 1, all should run
    # in parallel (~100ms), not serial (~300ms)
    assert elapsed < 250_000
  end

  # -------------------------------------------------------
  # Status
  # -------------------------------------------------------

  test "status returns zeros for unknown key", %{kp: kp} do
    assert KeyedPool.status(kp, :nothing) == %{running: 0, queued: 0}
  end

  test "status reflects running and queued counts" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 2)

    # Start 4 tasks on the same key (2 will run, 2 will queue)
    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :busy, fn ->
            Process.sleep(500)
            {:ok, :done}
          end)
        end)
      end

    # Wait for all to register
    Process.sleep(50)

    status = KeyedPool.status(kp, :busy)
    assert status.running == 2
    assert status.queued == 2

    Task.await_many(tasks, 10_000)

    # After completion, key should be cleaned up
    assert KeyedPool.status(kp, :busy) == %{running: 0, queued: 0}
  end

  # -------------------------------------------------------
  # Error handling — slot is freed on failure
  # -------------------------------------------------------

  test "crashed task frees its slot for queued callers" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)

    # First task crashes
    task1 =
      Task.async(fn ->
        KeyedPool.execute(kp, :crash, fn -> raise "boom" end)
      end)

    Process.sleep(30)

    # Second task should get the slot after the crash
    task2 =
      Task.async(fn ->
        KeyedPool.execute(kp, :crash, fn -> {:ok, :recovered} end)
      end)

    result1 = Task.await(task1, 5_000)
    result2 = Task.await(task2, 5_000)

    assert {:error, {:exception, %RuntimeError{message: "boom"}}} = result1
    assert result2 == {:ok, :recovered}
  end

  test "error result frees the slot", %{kp: kp} do
    {:ok, order} = Agent.start_link(fn -> [] end)

    # Fill both slots with errors, then queue successes
    tasks =
      for i <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :mixed, fn ->
            Agent.update(order, fn list -> list ++ [i] end)

            if i <= 2 do
              Process.sleep(100)
              {:error, :fail}
            else
              {:ok, :success}
            end
          end)
        end)
      end

    results = Task.await_many(tasks, 10_000)

    errors = Enum.count(results, &match?({:error, _}, &1))
    oks = Enum.count(results, &match?({:ok, _}, &1))
    assert errors == 2
    assert oks == 2
  end

  # -------------------------------------------------------
  # Key clearing
  # -------------------------------------------------------

  test "key is cleaned up when all work finishes", %{kp: kp} do
    KeyedPool.execute(kp, :temp, fn -> {:ok, :done} end)

    # After completion, status should be zero
    assert KeyedPool.status(kp, :temp) == %{running: 0, queued: 0}
  end

  # -------------------------------------------------------
  # GenServer responsiveness
  # -------------------------------------------------------

  test "GenServer is not blocked while tasks are running", %{kp: kp} do
    slow =
      Task.async(fn ->
        KeyedPool.execute(kp, :slow, fn ->
          Process.sleep(500)
          {:ok, :slow}
        end)
      end)

    Process.sleep(30)

    {elapsed, result} =
      :timer.tc(fn ->
        KeyedPool.execute(kp, :fast, fn -> {:ok, :fast} end)
      end)

    assert result == {:ok, :fast}
    assert elapsed < 200_000

    Task.await(slow, 5_000)
  end

  # -------------------------------------------------------
  # Named registration
  # -------------------------------------------------------

  test "named process registration works" do
    {:ok, _pid} = KeyedPool.start_link(max_concurrency: 2, name: :my_pool)

    assert {:ok, :hello} =
             KeyedPool.execute(:my_pool, :k, fn -> {:ok, :hello} end)
  end

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "start_link raises on invalid max_concurrency" do
    assert_raise ArgumentError, fn ->
      KeyedPool.start_link(max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      KeyedPool.start_link(max_concurrency: -1)
    end
  end

  # -------------------------------------------------------
  # Stress test
  # -------------------------------------------------------

  test "handles many callers across many keys" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 3)

    tasks =
      for key <- [:a, :b, :c, :d], i <- 1..10 do
        Task.async(fn ->
          KeyedPool.execute(kp, key, fn ->
            Process.sleep(10)
            {:ok, {key, i}}
          end)
        end)
      end

    results = Task.await_many(tasks, 30_000)

    assert length(results) == 40
    assert Enum.all?(results, &match?({:ok, {_, _}}, &1))
  end
end
