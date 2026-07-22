defmodule PooledFetcherTest do
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
  # Basic behaviour
  # -------------------------------------------------------

  test "returns ok for all sources when the pool is large enough" do
    sources = [
      {:a, slow_ok(:ra, 10)},
      {:b, slow_ok(:rb, 10)},
      {:c, slow_ok(:rc, 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 5, 1_000)

    assert result == %{a: {:ok, :ra}, b: {:ok, :rb}, c: {:ok, :rc}}
  end

  test "handles error returns and crashes without affecting other fetches" do
    sources = [
      {:ok_src, slow_ok(:a, 10)},
      {:err, slow_error(:bad, 10)},
      {:boom, slow_raise("x", 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 1_000)

    assert result[:ok_src] == {:ok, :a}
    assert result[:err] == {:error, :bad}
    assert {:error, %RuntimeError{message: "x"}} = result[:boom]
  end

  # -------------------------------------------------------
  # Bounded concurrency
  # -------------------------------------------------------

  test "runs at most max_concurrency fetches at a time" do
    # 6 fetches of 100ms through a pool of 2 => ~3 sequential batches (~300ms).
    sources = for i <- 1..6, do: {i, slow_ok(i, 100)}

    start = System.monotonic_time(:millisecond)
    result = PooledFetcher.fetch_all(sources, 2, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..6, fn i -> result[i] == {:ok, i} end)
    assert elapsed >= 250, "pool appears unbounded (took only #{elapsed}ms)"
    assert elapsed < 800, "pool is slower than expected (took #{elapsed}ms)"
  end

  test "sources still queued or running when the timeout fires are reported as :timeout" do
    sources = [
      {:s1, slow_ok(:one, 100)},
      {:s2, slow_ok(:two, 100)},
      {:s3, slow_ok(:three, 100)},
      {:s4, slow_ok(:four, 100)}
    ]

    result = PooledFetcher.fetch_all(sources, 1, 150)

    assert result[:s1] == {:ok, :one}
    assert result[:s2] == {:error, :timeout}
    assert result[:s3] == {:error, :timeout}
    assert result[:s4] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert PooledFetcher.fetch_all([], 3, 1_000) == %{}
  end

  test "supports arbitrary term keys" do
    sources = [
      {"s", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:t}, slow_ok(3, 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 1_000)

    assert result["s"] == {:ok, 1}
    assert result[42] == {:ok, 2}
    assert result[{:t}] == {:ok, 3}
  end

  test "single source" do
    assert PooledFetcher.fetch_all([{:only, slow_ok(:yes, 10)}], 2, 1_000) ==
             %{only: {:ok, :yes}}
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "timed-out and queued sources leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, slow_ok(i, 3_000)}
    PooledFetcher.fetch_all(sources, 3, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end

  # -------------------------------------------------------
  # A spent budget (timeout_ms: 0)
  # -------------------------------------------------------

  # A zero budget is already spent: the deadline check precedes any collection,
  # so every source reports {:error, :timeout} — even ones whose fetch_fn would
  # have returned instantly.
  test "timeout_ms 0 times out every source, even instantly-returning ones" do
    sources = for i <- 1..8, do: {i, fn -> {:ok, i} end}

    result = PooledFetcher.fetch_all(sources, 8, 0)

    assert map_size(result) == 8

    for i <- 1..8 do
      assert result[i] == {:error, :timeout},
             "source #{i} was collected despite an already-spent budget: #{inspect(result[i])}"
    end
  end

  # A source becomes {:error, :timeout} only when the deadline expires while it
  # is still running or queued; one that returned {:ok, value} in time keeps its
  # real result — a live budget must not be treated as already spent. Retried a
  # number of times because a 1ms budget is inherently tight: an implementation
  # that never collects an instant result inside a live budget fails every time.
  test "a live budget is not treated as spent: an instant fetch still gets collected" do
    outcomes =
      for _ <- 1..50 do
        PooledFetcher.fetch_all([{:fast, fn -> {:ok, :now} end}], 1, 1)[:fast]
      end

    assert Enum.any?(outcomes, &(&1 == {:ok, :now})),
           "an instant fetch was never collected within a live 1ms budget"
  end

  # -------------------------------------------------------
  # Failure normalisation
  # -------------------------------------------------------

  # Failure normalisation: throws become {:error, {:throw, value}}, exits become
  # {:error, {:exit, reason}}, and anything that is not an {:ok, _} / {:error, _}
  # tuple becomes {:error, {:unexpected_return, term}}.
  test "throws, exits and unexpected returns are normalised to tagged error tuples" do
    sources = [
      {:thrown, fn -> throw(:nope) end},
      {:exited, fn -> exit(:bye) end},
      {:bare_ok, fn -> :ok end},
      {:number, fn -> 42 end}
    ]

    result = PooledFetcher.fetch_all(sources, 4, 1_000)

    assert result[:thrown] == {:error, {:throw, :nope}}
    assert result[:exited] == {:error, {:exit, :bye}}
    assert result[:bare_ok] == {:error, {:unexpected_return, :ok}}
    assert result[:number] == {:error, {:unexpected_return, 42}}
  end

  # A fetch process that dies without delivering a result (e.g. killed from
  # outside the module) reports {:error, reason} with that process's exit
  # reason. The caller traps exits so the brutal kill of a linked fetch process
  # cannot take the test process down with it.
  test "a fetch process killed without delivering a result reports its exit reason" do
    trapping? = Process.flag(:trap_exit, true)

    try do
      sources = [
        {:killed, fn -> Process.exit(self(), :kill) end},
        {:healthy, fn -> {:ok, :done} end}
      ]

      result = PooledFetcher.fetch_all(sources, 2, 1_000)

      assert result[:killed] == {:error, :killed}
      assert result[:healthy] == {:ok, :done}
    after
      Process.flag(:trap_exit, trapping?)
    end
  end

  # -------------------------------------------------------
  # Guarded contract
  # -------------------------------------------------------

  # A max_concurrency that is not a positive integer, or a timeout_ms that is
  # not a non-negative integer, is outside the supported contract and must be
  # rejected by a guard rather than silently doing something surprising.
  test "a non-positive max_concurrency or negative timeout_ms is rejected by a guard" do
    sources = [{:a, fn -> {:ok, 1} end}]

    assert_raise FunctionClauseError, fn ->
      PooledFetcher.fetch_all(sources, 0, 100)
    end

    assert_raise FunctionClauseError, fn ->
      PooledFetcher.fetch_all(sources, -1, 100)
    end

    assert_raise FunctionClauseError, fn ->
      PooledFetcher.fetch_all(sources, 2, -1)
    end
  end
end
