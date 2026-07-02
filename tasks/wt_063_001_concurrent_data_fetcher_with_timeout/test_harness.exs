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
    sources = [
      {:a, slow_ok(:result_a, 10)},
      {:b, slow_ok(:result_b, 20)},
      {:c, slow_ok(:result_c, 5)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert result == %{
             a: {:ok, :result_a},
             b: {:ok, :result_b},
             c: {:ok, :result_c}
           }
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
