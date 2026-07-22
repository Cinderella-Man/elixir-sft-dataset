defmodule DedupTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Dedup.start_link([])
    %{dd: pid}
  end

  # -------------------------------------------------------
  # Basic execution
  # -------------------------------------------------------

  test "executes the function and returns the result", %{dd: dd} do
    assert {:ok, 42} = Dedup.execute(dd, "k", fn -> {:ok, 42} end)
  end

  test "wraps plain return values in an ok tuple", %{dd: dd} do
    assert {:ok, "hello"} = Dedup.execute(dd, "k", fn -> "hello" end)
  end

  test "passes through {:error, reason} as-is", %{dd: dd} do
    assert {:error, :boom} = Dedup.execute(dd, "k", fn -> {:error, :boom} end)
  end

  # -------------------------------------------------------
  # Deduplication — the core behaviour
  # -------------------------------------------------------

  test "concurrent calls with the same key execute the function exactly once", %{dd: dd} do
    # A counter to track how many times the function actually runs
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # The function sleeps a bit so concurrent callers pile up
    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(200)
      {:ok, :result}
    end

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> Dedup.execute(dd, "same_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    # All 10 callers got the same result
    assert Enum.all?(results, &(&1 == {:ok, :result}))

    # The function was called exactly once
    assert Agent.get(counter, & &1) == 1
  end

  test "different keys execute independently and concurrently", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(100)
      {:ok, :done}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "key:#{i}", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:ok, :done}))
    # Each distinct key triggers its own execution
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Key clearing after completion
  # -------------------------------------------------------

  test "key is cleared after successful execution, allowing a fresh call", %{dd: dd} do
    assert {:ok, 1} = Dedup.execute(dd, "k", fn -> {:ok, 1} end)
    # Second call should trigger a new execution, not return stale data
    assert {:ok, 2} = Dedup.execute(dd, "k", fn -> {:ok, 2} end)
  end

  test "key is cleared after error, allowing a fresh call", %{dd: dd} do
    assert {:error, :fail} = Dedup.execute(dd, "k", fn -> {:error, :fail} end)
    # Key is cleared, so this should trigger a new execution
    assert {:ok, :recovered} = Dedup.execute(dd, "k", fn -> {:ok, :recovered} end)
  end

  # -------------------------------------------------------
  # Error broadcasting
  # -------------------------------------------------------

  test "error result is broadcast to all waiting callers", %{dd: dd} do
    func = fn ->
      Process.sleep(200)
      {:error, :something_went_wrong}
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "err_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:error, :something_went_wrong}))
  end

  test "exception in func is broadcast as {:error, {:exception, _}}", %{dd: dd} do
    func = fn ->
      Process.sleep(100)
      raise "kaboom"
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "raise_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:error, {:exception, %RuntimeError{message: "kaboom"}}} -> true
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # GenServer responsiveness
  # -------------------------------------------------------

  test "GenServer is not blocked while a function is running", %{dd: dd} do
    # Start a slow execution on key "slow"
    slow_task =
      Task.async(fn ->
        Dedup.execute(dd, "slow", fn ->
          Process.sleep(500)
          {:ok, :slow_result}
        end)
      end)

    # Give it a moment to start
    Process.sleep(50)

    # A call on a different key should return quickly, not block
    {elapsed, result} =
      :timer.tc(fn ->
        Dedup.execute(dd, "fast", fn -> {:ok, :fast_result} end)
      end)

    assert result == {:ok, :fast_result}
    # Should be well under 500ms — the GenServer isn't blocked
    # microseconds
    assert elapsed < 200_000

    # Clean up
    Task.await(slow_task, 5_000)
  end

  # -------------------------------------------------------
  # Rapid sequential reuse of the same key
  # -------------------------------------------------------

  test "sequential calls on the same key each trigger their own execution", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    for _ <- 1..5 do
      Dedup.execute(dd, "seq", fn ->
        Agent.update(counter, &(&1 + 1))
        {:ok, :done}
      end)
    end

    # Each sequential call should have executed the function
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Mixed keys concurrent stress test
  # -------------------------------------------------------

  test "mixed concurrent calls on several keys", %{dd: dd} do
    {:ok, counters} = Agent.start_link(fn -> %{} end)

    tasks =
      for key <- ["a", "b", "c"], _ <- 1..10 do
        Task.async(fn ->
          Dedup.execute(dd, key, fn ->
            Agent.update(counters, fn map ->
              Map.update(map, key, 1, &(&1 + 1))
            end)

            Process.sleep(150)
            {:ok, key}
          end)
        end)
      end

    results = Task.await_many(tasks, 10_000)

    # All callers for each key should get the same result
    for key <- ["a", "b", "c"] do
      key_results = Enum.filter(results, &(&1 == {:ok, key}))
      assert length(key_results) == 10
    end

    # Each key's function was called exactly once
    counts = Agent.get(counters, & &1)
    assert counts["a"] == 1
    assert counts["b"] == 1
    assert counts["c"] == 1
  end
end
