# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule DecayPercentileTest do
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
    opts =
      opts
      |> Keyword.put_new(:clock, &Clock.now/0)
      |> Keyword.put_new(:half_life_ms, 1_000)

    start_supervised!({DecayPercentile, opts})
    :ok
  end

  # ---------------------------------------------------------
  # Base nearest-rank behavior when all samples are fresh
  # ---------------------------------------------------------

  test "with equal fresh weights, percentiles match plain nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert(:ok = DecayPercentile.record(:d, v))

    assert {:ok, 50} = DecayPercentile.query(:d, 0.50)
    assert {:ok, 95} = DecayPercentile.query(:d, 0.95)
    assert {:ok, 1} = DecayPercentile.query(:d, 0.0)
    assert {:ok, 100} = DecayPercentile.query(:d, 1.0)
  end

  test "single sample returns that sample for any percentile" do
    start_server([])
    DecayPercentile.record(:one, 42)

    assert {:ok, 42} = DecayPercentile.query(:one, 0.0)
    assert {:ok, 42} = DecayPercentile.query(:one, 0.5)
    assert {:ok, 42} = DecayPercentile.query(:one, 1.0)
  end

  test "unknown series is empty" do
    start_server([])
    assert {:error, :empty} = DecayPercentile.query(:nope, 0.5)
    assert {:error, :empty} = DecayPercentile.total_weight(:nope)
  end

  # ---------------------------------------------------------
  # The defining decay behavior
  # ---------------------------------------------------------

  test "a fresh sample outweighs an old one and shifts the median" do
    start_server([])

    # old, low value at t=0
    DecayPercentile.record(:t, 1)

    # 3 half-lives later: old weight = 0.125, new weight = 1.0
    Clock.advance(3_000)
    DecayPercentile.record(:t, 100)

    # W = 1.125, target for p50 = 0.5625; cumulative at 1 is only 0.125,
    # so the median is pulled all the way up to the fresh sample.
    assert {:ok, 100} = DecayPercentile.query(:t, 0.50)
  end

  test "uniform aging does not change the reported percentile" do
    start_server([])

    DecayPercentile.record(:t, 1)
    DecayPercentile.record(:t, 100)

    # both fresh: nearest-rank median (lower of two) is 1
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)

    # advance the clock with no new records: both weights scale equally
    Clock.advance(3_000)
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)
  end

  test "total_weight reflects exponential decay of a single sample" do
    start_server([])
    DecayPercentile.record(:w, 5)

    assert {:ok, w0} = DecayPercentile.total_weight(:w)
    assert_in_delta w0, 1.0, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w1} = DecayPercentile.total_weight(:w)
    assert_in_delta w1, 0.5, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w2} = DecayPercentile.total_weight(:w)
    assert_in_delta w2, 0.25, 1.0e-9
  end

  # ---------------------------------------------------------
  # Fully underflowed weights read as empty, not as a stale value
  # ---------------------------------------------------------

  test "series whose weights have all underflowed to zero reports empty" do
    start_server([])

    DecayPercentile.record(:u, 1)
    DecayPercentile.record(:u, 50)
    DecayPercentile.record(:u, 100)

    # 2000 half-lives: every 0.5 ^ (age / half_life) underflows to 0.0, so the
    # series holds samples but carries no weight at all.
    Clock.advance(2_000_000)

    assert {:error, :empty} = DecayPercentile.query(:u, 0.0)
    assert {:error, :empty} = DecayPercentile.query(:u, 0.5)
    assert {:error, :empty} = DecayPercentile.query(:u, 1.0)
    assert {:error, :empty} = DecayPercentile.total_weight(:u)
  end

  test "recording after total underflow makes the series report the fresh sample" do
    start_server([])

    DecayPercentile.record(:u2, 1)
    Clock.advance(2_000_000)
    assert {:error, :empty} = DecayPercentile.query(:u2, 0.5)

    # The fresh sample has weight 1.0 while the underflowed one contributes 0.0,
    # so it alone determines every percentile.
    DecayPercentile.record(:u2, 7)

    assert {:ok, 7} = DecayPercentile.query(:u2, 0.0)
    assert {:ok, 7} = DecayPercentile.query(:u2, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:u2)
    assert_in_delta w, 1.0, 1.0e-9
  end

  # ---------------------------------------------------------
  # Bounded memory & housekeeping
  # ---------------------------------------------------------

  test "max_samples bounds retained samples, dropping oldest" do
    start_server(max_samples: 5)
    for v <- 1..10, do: DecayPercentile.record(:c, v)

    # only [6,7,8,9,10] remain; all recorded at t=0 => equal weights
    assert {:ok, 6} = DecayPercentile.query(:c, 0.0)
    assert {:ok, 10} = DecayPercentile.query(:c, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:c)
    assert_in_delta w, 5.0, 1.0e-9
  end

  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: DecayPercentile.record(:r, v)
    assert :ok = DecayPercentile.reset(:r)
    assert {:error, :empty} = DecayPercentile.query(:r, 0.5)
  end

  test "series are independent" do
    start_server([])
    DecayPercentile.record(:a, 1)
    DecayPercentile.record(:b, 999)

    assert {:ok, 1} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)

    DecayPercentile.reset(:a)
    assert {:error, :empty} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)
  end

  test "underflow in one series leaves a freshly recorded series unaffected" do
    start_server([])

    DecayPercentile.record(:old, 1)
    Clock.advance(2_000_000)
    DecayPercentile.record(:new, 42)

    assert {:error, :empty} = DecayPercentile.query(:old, 0.5)
    assert {:error, :empty} = DecayPercentile.total_weight(:old)
    assert {:ok, 42} = DecayPercentile.query(:new, 0.5)
  end

  test "invalid half_life raises" do
    assert_raise ArgumentError, fn ->
      DecayPercentile.start_link(name: :bad, clock: &Clock.now/0, half_life_ms: 0)
    end
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
