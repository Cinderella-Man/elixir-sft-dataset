defmodule FallbackFetcherTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp fast_ok(value), do: fn -> {:ok, value} end
  defp fast_error(reason), do: fn -> {:error, reason} end
  defp fast_raise(msg), do: fn -> raise RuntimeError, msg end

  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  # -------------------------------------------------------
  # Fallback-chain behaviour
  # -------------------------------------------------------

  test "uses the first fallback when it succeeds" do
    result = FallbackFetcher.fetch_all([{:a, [fast_ok(:first), fast_ok(:second)]}], 1_000)
    assert result[:a] == {:ok, :first}
  end

  test "falls through to the next fallback on error" do
    result = FallbackFetcher.fetch_all([{:a, [fast_error(:down), fast_ok(:backup)]}], 1_000)
    assert result[:a] == {:ok, :backup}
  end

  test "treats a raising fallback as a failure and continues" do
    result = FallbackFetcher.fetch_all([{:a, [fast_raise("boom"), fast_ok(:recovered)]}], 1_000)
    assert result[:a] == {:ok, :recovered}
  end

  test "reports all_failed with the ordered list of reasons when every fallback fails" do
    result =
      FallbackFetcher.fetch_all(
        [{:a, [fast_error(:one), fast_error(:two), fast_raise("three")]}],
        1_000
      )

    assert {:error, {:all_failed, reasons}} = result[:a]
    assert length(reasons) == 3
    assert Enum.at(reasons, 0) == :one
    assert Enum.at(reasons, 1) == :two
    assert %RuntimeError{message: "three"} = Enum.at(reasons, 2)
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "a chain that overruns the global timeout is reported as :timeout" do
    sources = [
      {:fast, [fast_ok(:done)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:fast] == {:ok, :done}
    assert result[:slow] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "sources run concurrently, not sequentially" do
    sources = for i <- 1..5, do: {i, [slow_ok(i, 100)]}

    start = System.monotonic_time(:millisecond)
    result = FallbackFetcher.fetch_all(sources, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..5, fn i -> result[i] == {:ok, i} end)
    assert elapsed < 300, "fetches appear sequential (took #{elapsed}ms)"
  end

  # -------------------------------------------------------
  # Edge cases and no zombies
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert FallbackFetcher.fetch_all([], 1_000) == %{}
  end

  test "timed-out chains leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, [slow_ok(i, 3_000)]}
    FallbackFetcher.fetch_all(sources, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end

  test "mixes success, exhausted fallbacks, and timeout" do
    sources = [
      {:ok_src, [fast_error(:x), fast_ok(:good)]},
      {:dead, [fast_error(:a), fast_error(:b)]},
      {:slow, [slow_ok(:never, 2_000)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:ok_src] == {:ok, :good}
    assert {:error, {:all_failed, [:a, :b]}} = result[:dead]
    assert result[:slow] == {:error, :timeout}
  end

  test "the budget spans the whole chain, not each fallback separately" do
    slow_fail = fn ->
      Process.sleep(100)
      {:error, :slow_fail}
    end

    sources = [{:chain, [slow_fail, slow_fail, slow_fail]}]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:chain] == {:error, :timeout}
  end

  test "every spawned worker is already dead by the time fetch_all returns" do
    test_pid = self()

    announce_then_hang = fn ->
      send(test_pid, {:worker, self()})
      Process.sleep(5_000)
      {:ok, :never}
    end

    sources = for i <- 1..3, do: {i, [announce_then_hang]}

    result = FallbackFetcher.fetch_all(sources, 100)

    assert Enum.all?(1..3, fn i -> result[i] == {:error, :timeout} end)

    pids =
      for _ <- 1..3 do
        assert_receive {:worker, pid}, 500
        pid
      end

    for pid <- pids do
      refute Process.alive?(pid), "worker #{inspect(pid)} was still alive when fetch_all returned"
    end
  end

  test "a killed source does not go on to try its remaining fallbacks" do
    test_pid = self()

    slow_fail = fn ->
      Process.sleep(300)
      {:error, :too_slow}
    end

    after_kill = fn ->
      send(test_pid, :next_fallback_ran)
      {:ok, :nope}
    end

    result = FallbackFetcher.fetch_all([{:s, [slow_fail, after_kill]}], 100)

    assert result[:s] == {:error, :timeout}
    refute_receive :next_fallback_ran, 600
  end

  test "keys the result map by arbitrary source names" do
    sources = [
      {"string-name", [fn -> {:ok, :s} end]},
      {{:tuple, 1}, [fn -> {:error, :nope} end]},
      {42, [fn -> {:ok, :n} end]},
      {[:list, "mixed"], [fn -> {:ok, :l} end]}
    ]

    result = FallbackFetcher.fetch_all(sources, 1_000)

    assert result["string-name"] == {:ok, :s}
    assert result[{:tuple, 1}] == {:error, {:all_failed, [:nope]}}
    assert result[42] == {:ok, :n}
    assert result[[:list, "mixed"]] == {:ok, :l}
  end
end
