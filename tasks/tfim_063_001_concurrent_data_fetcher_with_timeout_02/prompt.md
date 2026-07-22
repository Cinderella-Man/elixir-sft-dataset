# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ConcurrentFetcher do
  @moduledoc """
  Fetches data from multiple sources concurrently under a single global timeout.

  All fetches begin at the same instant. The timeout budget is shared — it is
  not reset or re-applied per source. Any source that has not completed by the
  time the deadline fires is killed immediately and reported as
  `{:error, :timeout}`.
  """

  @doc """
  Fetch from all sources concurrently, returning results within `timeout_ms`.

  ## Parameters
  - `sources`    – list of `{name, fetch_fn}` tuples.
                   `name` is any term; `fetch_fn` is a zero-arity function
                   returning `{:ok, value}` or `{:error, reason}` (raising is
                   also handled gracefully).
  - `timeout_ms` – global wall-clock budget in milliseconds, shared by every
                   concurrent fetch.

  ## Return value
  A map of `%{name => result_tuple}` where each value is one of:

  - `{:ok, value}`          – fetch completed successfully within the timeout
  - `{:error, :timeout}`    – global timeout expired before this fetch finished
  - `{:error, reason}`      – fetch function raised or returned `{:error, reason}`

  Returns `%{}` immediately when `sources` is empty.
  """
  @spec fetch_all([{term(), (-> {:ok, term()} | {:error, term()})}], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms)
      when is_list(sources) and is_integer(timeout_ms) and timeout_ms >= 0 do
    # ── 1. Spawn every fetch concurrently ──────────────────────────────────
    # Task.async/1 links the task to the caller, which lets us kill it later
    # via Task.shutdown/2. We pair each Task struct with its source name so we
    # can reconstruct the result map afterwards.
    tagged_tasks =
      Enum.map(sources, fn {name, fetch_fn} ->
        task = Task.async(fn -> safe_call(fetch_fn) end)
        {name, task}
      end)

    tasks = Enum.map(tagged_tasks, fn {_name, task} -> task end)

    # ── 2. Wait for all tasks under the global timeout ─────────────────────
    # Task.yield_many/2 blocks for at most `timeout_ms` milliseconds and then
    # returns a list of {task, result_or_nil} pairs in the same order as the
    # input list.  A nil result means the task did not finish in time.
    yield_results = Task.yield_many(tasks, timeout_ms)

    # ── 3. Reconcile each task's outcome ──────────────────────────────────
    # Build a map from task reference → final result_tuple first, then
    # re-attach names.
    ref_to_result =
      Enum.reduce(yield_results, %{}, fn {task, yield_outcome}, acc ->
        result =
          case yield_outcome do
            # Task completed within the timeout window.
            {:ok, {:ok, value}} ->
              {:ok, value}

            # Task completed but returned an application-level error.
            {:ok, {:error, reason}} ->
              {:error, reason}

            # Task exited/raised before the timeout fired.
            {:exit, reason} ->
              {:error, reason}

            # Timeout: the task is still running — shut it down immediately.
            # Task.shutdown/2 sends an exit signal and waits for the process
            # to terminate, so no zombie processes are left behind.
            nil ->
              Task.shutdown(task, :brutal_kill)
              {:error, :timeout}
          end

        Map.put(acc, task.ref, result)
      end)

    # ── 4. Rebuild the caller-facing map keyed by source name ─────────────
    Map.new(tagged_tasks, fn {name, task} ->
      {name, Map.fetch!(ref_to_result, task.ref)}
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Wraps the user-supplied fetch function so that any exception or unexpected
  # return value is normalised into {:ok, _} | {:error, _} without leaking raw
  # EXIT signals to the caller.
  defp safe_call(fetch_fn) do
    case fetch_fn.() do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, value -> {:error, {kind, value}}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ConcurrentFetcherTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Returns a fetch_fn that completes after `delay_ms` with {:ok, value}
  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  # Returns a fetch_fn that completes after `delay_ms` then raises
  defp slow_raise(msg, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      raise RuntimeError, msg
    end
  end

  # Returns a fetch_fn that completes after `delay_ms` with {:error, reason}
  defp slow_error(reason, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:error, reason}
    end
  end

  # -------------------------------------------------------
  # Basic functionality
  # -------------------------------------------------------

  test "returns ok for all fast fetches" do
    # TODO
  end

  test "returns error tuple for fetch functions that raise" do
    sources = [
      {:good, slow_ok(:fine, 10)},
      {:bad, slow_raise("boom", 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, :fine} = result[:good]
    assert {:error, reason} = result[:bad]
    assert reason != :timeout
  end

  test "returns error tuple for fetch functions that return {:error, reason}" do
    sources = [
      {:good, slow_ok(:fine, 10)},
      {:bad, slow_error(:something_went_wrong, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, :fine} = result[:good]
    assert {:error, :something_went_wrong} = result[:bad]
  end

  test "empty sources returns empty map" do
    assert %{} == ConcurrentFetcher.fetch_all([], 1_000)
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "slow fetches are reported as :timeout" do
    sources = [
      {:fast, slow_ok(:done, 20)},
      {:slow, slow_ok(:never, 600)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 150)

    assert {:ok, :done} = result[:fast]
    assert {:error, :timeout} = result[:slow]
  end

  test "all fetches time out when all are slow" do
    sources = [
      {:a, slow_ok(:a, 500)},
      {:b, slow_ok(:b, 600)},
      {:c, slow_ok(:c, 700)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 100)

    assert {:error, :timeout} = result[:a]
    assert {:error, :timeout} = result[:b]
    assert {:error, :timeout} = result[:c]
  end

  test "mix of fast, slow, and failing sources" do
    sources = [
      {:fast, slow_ok(:winner, 20)},
      {:slow, slow_ok(:loser, 800)},
      {:crasher, slow_raise("oops", 10)},
      {:erring, slow_error(:bad_input, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 200)

    assert {:ok, :winner} = result[:fast]
    assert {:error, :timeout} = result[:slow]
    assert {:error, _} = result[:crasher]
    assert {:error, :bad_input} = result[:erring]
  end

  test "fetch_all returns within a reasonable margin of the timeout" do
    sources = [
      {:slow, slow_ok(:never, 10_000)}
    ]

    timeout_ms = 150
    start = System.monotonic_time(:millisecond)
    ConcurrentFetcher.fetch_all(sources, timeout_ms)
    elapsed = System.monotonic_time(:millisecond) - start

    # Should return close to the timeout, not wait for the slow fetch
    assert elapsed < timeout_ms + 200
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "timed-out tasks leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources =
      for i <- 1..10 do
        {i, slow_ok(i, 2_000)}
      end

    ConcurrentFetcher.fetch_all(sources, 100)

    # Give the VM a moment to finish any teardown
    Process.sleep(50)

    after_pids = MapSet.new(Process.list())
    new_pids = MapSet.difference(after_pids, before_pids)

    assert MapSet.size(new_pids) == 0,
           "Expected no leftover processes, found: #{inspect(MapSet.to_list(new_pids))}"
  end

  # -------------------------------------------------------
  # Concurrency — fetches run in parallel
  # -------------------------------------------------------

  test "all fetches run concurrently, not sequentially" do
    # 5 fetches each taking 100 ms. Sequential would take ~500 ms.
    # Concurrent should finish well under 300 ms.
    sources =
      for i <- 1..5 do
        {i, slow_ok(i, 100)}
      end

    start = System.monotonic_time(:millisecond)
    result = ConcurrentFetcher.fetch_all(sources, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..5, fn i -> result[i] == {:ok, i} end)
    assert elapsed < 300, "Fetches appear to be sequential (took #{elapsed}ms)"
  end

  # -------------------------------------------------------
  # Key types
  # -------------------------------------------------------

  test "supports arbitrary term keys" do
    sources = [
      {"string_key", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:tuple}, slow_ok(3, 10)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert {:ok, 1} = result["string_key"]
    assert {:ok, 2} = result[42]
    assert {:ok, 3} = result[{:tuple}]
  end

  # -------------------------------------------------------
  # Single source edge case
  # -------------------------------------------------------

  test "single fast source" do
    result = ConcurrentFetcher.fetch_all([{:only, slow_ok(:yes, 10)}], 500)
    assert %{only: {:ok, :yes}} = result
  end

  test "single timed-out source" do
    result = ConcurrentFetcher.fetch_all([{:only, slow_ok(:yes, 500)}], 50)
    assert %{only: {:error, :timeout}} = result
  end
end
```
