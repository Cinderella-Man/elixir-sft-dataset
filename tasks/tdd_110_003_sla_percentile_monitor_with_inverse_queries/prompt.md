# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule RankPercentileTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})
    :ok
  end

  defp start_server(opts) do
    start_supervised!({RankPercentile, Keyword.put_new(opts, :clock, &Clock.now/0)})
    :ok
  end

  # ---------------------------------------------------------
  # Forward query (nearest-rank)
  # ---------------------------------------------------------

  test "forward percentile query matches nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert(:ok = RankPercentile.record(:d, v))

    assert {:ok, 50} = RankPercentile.query(:d, 0.50)
    assert {:ok, 95} = RankPercentile.query(:d, 0.95)
    assert {:ok, 1} = RankPercentile.query(:d, 0.0)
    assert {:ok, 100} = RankPercentile.query(:d, 1.0)
  end

  # ---------------------------------------------------------
  # Inverse query: rank / empirical CDF
  # ---------------------------------------------------------

  test "rank returns the fraction of samples at or below a value" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 0.5} = RankPercentile.rank(:d, 50)
    assert {:ok, 0.01} = RankPercentile.rank(:d, 1)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 100)
  end

  test "rank clamps below min and above max" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:d, v)

    assert {:ok, +0.0} = RankPercentile.rank(:d, 0)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 999)
  end

  test "rank on an empty series is :empty" do
    start_server([])
    assert {:error, :empty} = RankPercentile.rank(:nope, 5)
  end

  # ---------------------------------------------------------
  # count_above (SLA violations)
  # ---------------------------------------------------------

  test "count_above counts samples strictly greater than the threshold" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 5} = RankPercentile.count_above(:d, 95)
    assert {:ok, 100} = RankPercentile.count_above(:d, 0)
    assert {:ok, 0} = RankPercentile.count_above(:d, 100)
  end

  test "count_above on an empty series returns zero" do
    start_server([])
    assert {:ok, 0} = RankPercentile.count_above(:nope, 5)
  end

  # ---------------------------------------------------------
  # Windowing applies to every query direction
  # ---------------------------------------------------------

  test "expired samples drop out of query, rank, and count_above" do
    start_server(window_ms: 1_000)

    for v <- 1..50, do: RankPercentile.record(:t, v)

    Clock.advance(1_000)

    for v <- 60..69, do: RankPercentile.record(:t, v)

    # only [60..69] are live now
    assert {:ok, 64} = RankPercentile.query(:t, 0.50)
    assert {:ok, 0.5} = RankPercentile.rank(:t, 64)
    assert {:ok, 5} = RankPercentile.count_above(:t, 64)
  end

  test "count-based window keeps only the most recent samples" do
    start_server(max_samples: 5)
    for v <- 1..10, do: RankPercentile.record(:c, v)

    # only [6,7,8,9,10] remain
    assert {:ok, 6} = RankPercentile.query(:c, 0.0)
    assert {:ok, 0.2} = RankPercentile.rank(:c, 6)
    assert {:ok, 2} = RankPercentile.count_above(:c, 8)
  end

  # ---------------------------------------------------------
  # Reset & independence
  # ---------------------------------------------------------

  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:r, v)
    assert :ok = RankPercentile.reset(:r)
    assert {:error, :empty} = RankPercentile.query(:r, 0.5)
    assert {:ok, 0} = RankPercentile.count_above(:r, 0)
  end

  test "series are independent" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:a, v)
    for v <- 200..209, do: RankPercentile.record(:b, v)

    assert {:ok, 0.5} = RankPercentile.rank(:a, 50)
    assert {:ok, +0.0} = RankPercentile.rank(:b, 100)
    assert {:ok, 10} = RankPercentile.count_above(:b, 100)
  end

  test "time and count windows both apply when combined" do
    start_server(window_ms: 1_000, max_samples: 3)

    for v <- 1..5, do: RankPercentile.record(:m, v)

    # count window keeps only [3, 4, 5]
    assert {:ok, 3} = RankPercentile.query(:m, 0.0)
    assert {:ok, 5} = RankPercentile.query(:m, 1.0)
    assert {:ok, 2} = RankPercentile.count_above(:m, 3)
    assert {:ok, q} = RankPercentile.rank(:m, 3)
    assert_in_delta q, 1 / 3, 0.000_001

    # the time window then expires the survivors too
    Clock.advance(1_000)
    assert {:error, :empty} = RankPercentile.query(:m, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:m, 3)
    assert {:ok, 0} = RankPercentile.count_above(:m, 0)
  end

  test "a fully expired series behaves exactly like a never-recorded one" do
    start_server(window_ms: 500)

    for v <- 1..3, do: RankPercentile.record(:gone, v)

    assert {:ok, 2} = RankPercentile.query(:gone, 0.5)

    Clock.advance(500)

    assert {:error, :empty} = RankPercentile.query(:gone, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:gone, 2)
    assert {:ok, 0} = RankPercentile.count_above(:gone, 0)

    # identical answers for a series that was never recorded at all
    assert {:error, :empty} = RankPercentile.query(:never, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:never, 2)
    assert {:ok, 0} = RankPercentile.count_above(:never, 0)
  end

  test "a sample stays live until elapsed time reaches window_ms exactly" do
    start_server(window_ms: 1_000)

    RankPercentile.record(:edge, 7)

    Clock.advance(999)
    assert {:ok, 7} = RankPercentile.query(:edge, 0.5)
    assert {:ok, 1.0} = RankPercentile.rank(:edge, 7)
    assert {:ok, 1} = RankPercentile.count_above(:edge, 6)

    # now - t == window_ms is no longer strictly less than the window
    Clock.advance(1)
    assert {:error, :empty} = RankPercentile.query(:edge, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:edge, 7)
    assert {:ok, 0} = RankPercentile.count_above(:edge, 6)
  end

  test "query rejects percentiles outside the documented range" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:g, v)

    assert_raise FunctionClauseError, fn -> RankPercentile.query(:g, 1.5) end
    assert_raise FunctionClauseError, fn -> RankPercentile.query(:g, -0.5) end

    # the boundaries themselves remain accepted
    assert {:ok, 1} = RankPercentile.query(:g, 0.0)
    assert {:ok, 10} = RankPercentile.query(:g, 1.0)
  end

  test "duplicate sample values each count toward the empirical CDF" do
    start_server([])
    for v <- [5, 5, 5, 10], do: RankPercentile.record(:dup, v)

    assert {:ok, 0.75} = RankPercentile.rank(:dup, 5)
    assert {:ok, +0.0} = RankPercentile.rank(:dup, 4)
    assert {:ok, 1.0} = RankPercentile.rank(:dup, 10)
    assert {:ok, 5} = RankPercentile.query(:dup, 0.5)
    assert {:ok, 1} = RankPercentile.count_above(:dup, 5)
  end

  test "the process registers under the default name when none is given" do
    start_server([])

    assert is_pid(Process.whereis(RankPercentile))
    assert :ok = RankPercentile.record(:n, 1)
    assert {:ok, 1} = RankPercentile.query(:n, 0.5)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
