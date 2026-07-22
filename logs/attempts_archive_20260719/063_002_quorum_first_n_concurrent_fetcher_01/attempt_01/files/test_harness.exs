defmodule QuorumFetcherTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  defp slow_error(reason, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:error, reason}
    end
  end

  defp slow_raise(msg, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      raise RuntimeError, msg
    end
  end

  # -------------------------------------------------------
  # Quorum behaviour
  # -------------------------------------------------------

  test "returns as soon as the quorum of successes is reached and cancels the rest" do
    sources = [
      {:a, slow_ok(:ra, 20)},
      {:b, slow_ok(:rb, 20)},
      {:c, slow_ok(:rc, 20)},
      {:d, slow_ok(:rd, 3_000)},
      {:e, slow_ok(:re, 3_000)}
    ]

    start = System.monotonic_time(:millisecond)
    result = QuorumFetcher.fetch_first(sources, 3, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert result[:a] == {:ok, :ra}
    assert result[:b] == {:ok, :rb}
    assert result[:c] == {:ok, :rc}
    assert result[:d] == {:error, :cancelled}
    assert result[:e] == {:error, :cancelled}
    assert elapsed < 500, "should not wait for the slow sources (took #{elapsed}ms)"
  end

  test "sources that finish with an error do not count toward the quorum" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert result[:err] == {:error, :nope}
    assert result[:win] == {:ok, :yes}
  end

  test "a crashing source is reported as an error, not a success" do
    sources = [
      {:boom, slow_raise("kaboom", 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert {:error, reason} = result[:boom]
    assert reason != :cancelled
    assert reason != :timeout
    assert result[:win] == {:ok, :yes}
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "still-running sources become :timeout when the quorum can't be met in time" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)},
      {:c, slow_ok(:c, 3_000)},
      {:d, slow_ok(:d, 3_000)},
      {:e, slow_ok(:e, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 5, 150)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:ok, :b}
    assert result[:c] == {:error, :timeout}
    assert result[:d] == {:error, :timeout}
    assert result[:e] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert QuorumFetcher.fetch_first([], 3, 1_000) == %{}
  end

  test "a non-positive quorum cancels every source without running it" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 0, 1_000)

    assert result == %{a: {:error, :cancelled}, b: {:error, :cancelled}}
  end

  test "supports arbitrary term keys" do
    sources = [
      {"s", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:t}, slow_ok(3, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 1_000)

    assert result["s"] == {:ok, 1}
    assert result[42] == {:ok, 2}
    assert result[{:t}] == {:ok, 3}
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "cancelled and timed-out sources leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, slow_ok(i, 3_000)}

    QuorumFetcher.fetch_first(sources, 2, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end
end