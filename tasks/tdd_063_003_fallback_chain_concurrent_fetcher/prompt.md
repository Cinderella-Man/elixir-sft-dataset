# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  defp slow_error(reason, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:error, reason}
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

  # The budget covers the whole chain summed sequentially, not each fallback on
  # its own: three 100ms attempts overrun a 150ms budget even though no single
  # attempt does.
  test "a chain whose fallbacks sum past the global timeout is reported as :timeout" do
    sources = [
      {:fast, [fast_ok(:done)]},
      {:chained, [slow_error(:one, 100), slow_error(:two, 100), slow_ok(:three, 100)]}
    ]

    result = FallbackFetcher.fetch_all(sources, 150)

    assert result[:fast] == {:ok, :done}
    assert result[:chained] == {:error, :timeout}
  end

  # The mirror case: a multi-step chain whose summed work fits inside the budget
  # runs to its successful fallback.
  test "a chain whose fallbacks sum within the global timeout succeeds on a later fallback" do
    sources = [{:chained, [slow_error(:one, 30), slow_error(:two, 30), slow_ok(:three, 30)]}]

    result = FallbackFetcher.fetch_all(sources, 2_000)

    assert result[:chained] == {:ok, :three}
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
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
