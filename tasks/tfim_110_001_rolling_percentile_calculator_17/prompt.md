# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Percentile do
  @moduledoc """
  A GenServer that maintains rolling windows of numeric samples across many
  independent **series** and computes percentiles on demand using the
  nearest-rank method.

  A single running process manages any number of series, each identified by an
  arbitrary `name` term. Two independent windowing strategies are supported and
  may be combined:

    * time-based (`:window_ms`) — a sample recorded at time `t` is live while
      `now - t < window_ms`.
    * count-based (`:max_samples`) — only the most recently recorded
      `max_samples` samples per series are retained.

  All timestamps are produced by an injectable `:clock` function so time can be
  controlled deterministically in tests.
  """

  use GenServer

  @default_name Percentile

  ## Public API

  @doc """
  Starts and registers the process.

  ## Options

    * `:name` — the name to register the process under. Default: `Percentile`.
    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    * `:window_ms` — positive integer enabling a time-based window.
    * `:max_samples` — positive integer enabling a count-based window.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a numeric `value` into series `name`, timestamped with the current
  clock time. Returns `:ok`.
  """
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @doc """
  Computes the requested `percentile` (a float in `0.0..1.0`) over the currently
  live samples of series `name`.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series has no live samples.
  """
  @spec query(term, float) :: {:ok, number} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @doc """
  Discards all samples for series `name`. Returns `:ok`.
  """
  @spec reset(term) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = validate_positive(Keyword.get(opts, :window_ms))
    max_samples = validate_positive(Keyword.get(opts, :max_samples))

    state = %{
      clock: clock,
      window_ms: window_ms,
      max_samples: max_samples,
      # series name => list of {timestamp, value}, newest first
      series: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    live =
      state.series
      |> Map.get(name, [])
      |> live_samples(now, state.window_ms)
      |> Enum.map(fn {_t, v} -> v end)
      |> Enum.sort()

    {:reply, percentile_of(live, percentile), state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp validate_positive(nil), do: nil

  defp validate_positive(n) when is_integer(n) and n > 0, do: n

  defp validate_positive(other) do
    raise ArgumentError, "expected a positive integer, got: #{inspect(other)}"
  end

  defp enforce_max(samples, nil), do: samples
  defp enforce_max(samples, max), do: Enum.take(samples, max)

  defp live_samples(samples, _now, nil), do: samples

  defp live_samples(samples, now, window_ms) do
    Enum.filter(samples, fn {t, _v} -> now - t < window_ms end)
  end

  defp percentile_of([], _percentile), do: {:error, :empty}

  defp percentile_of(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PercentileTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic time-based windows ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})
    :ok
  end

  defp start_server(opts) do
    start_supervised!({Percentile, Keyword.put_new(opts, :clock, &Clock.now/0)})
    :ok
  end

  # -------------------------------------------------------
  # Nearest-rank correctness on a known distribution
  # -------------------------------------------------------

  test "p50/p95/p99 over 1..100 match nearest-rank" do
    start_server([])

    for v <- 1..100, do: assert(:ok = Percentile.record(:d, v))

    assert {:ok, 50} = Percentile.query(:d, 0.50)
    assert {:ok, 95} = Percentile.query(:d, 0.95)
    assert {:ok, 99} = Percentile.query(:d, 0.99)
  end

  test "p0 returns the min and p100 returns the max" do
    start_server([])

    for v <- 1..100, do: Percentile.record(:d, v)

    assert {:ok, 1} = Percentile.query(:d, 0.0)
    assert {:ok, 100} = Percentile.query(:d, 1.0)
  end

  test "unsorted input is handled correctly" do
    start_server([])

    for v <- Enum.shuffle(1..10), do: Percentile.record(:d, v)

    assert {:ok, 1} = Percentile.query(:d, 0.0)
    assert {:ok, 10} = Percentile.query(:d, 1.0)
    # nearest-rank p50 of 10 samples: ceil(0.5*10) = 5 -> s_5 = 5
    assert {:ok, 5} = Percentile.query(:d, 0.50)
  end

  test "large distribution 1..10000 is exact" do
    start_server([])

    for v <- 1..10_000, do: Percentile.record(:big, v)

    assert {:ok, 5_000} = Percentile.query(:big, 0.50)
    assert {:ok, 9_500} = Percentile.query(:big, 0.95)
    assert {:ok, 9_900} = Percentile.query(:big, 0.99)
    assert {:ok, 10_000} = Percentile.query(:big, 1.0)
  end

  test "float samples are supported" do
    start_server([])

    for v <- [1.5, 2.5, 3.5, 4.5], do: Percentile.record(:f, v)

    assert {:ok, 1.5} = Percentile.query(:f, 0.0)
    assert {:ok, 4.5} = Percentile.query(:f, 1.0)
    # ceil(0.5*4) = 2 -> s_2 = 2.5
    assert {:ok, 2.5} = Percentile.query(:f, 0.50)
  end

  # -------------------------------------------------------
  # Empty / single-sample behavior
  # -------------------------------------------------------

  test "querying an unknown series returns :empty" do
    start_server([])
    assert {:error, :empty} = Percentile.query(:nope, 0.5)
  end

  test "single sample returns that sample for any percentile" do
    start_server([])
    Percentile.record(:one, 42)

    assert {:ok, 42} = Percentile.query(:one, 0.0)
    assert {:ok, 42} = Percentile.query(:one, 0.5)
    assert {:ok, 42} = Percentile.query(:one, 1.0)
  end

  # -------------------------------------------------------
  # Reset
  # -------------------------------------------------------

  test "reset clears a series" do
    start_server([])

    for v <- 1..10, do: Percentile.record(:r, v)
    assert {:ok, _} = Percentile.query(:r, 0.5)

    assert :ok = Percentile.reset(:r)
    assert {:error, :empty} = Percentile.query(:r, 0.5)

    # can be reused after reset
    Percentile.record(:r, 7)
    assert {:ok, 7} = Percentile.query(:r, 0.5)
  end

  # -------------------------------------------------------
  # Series independence
  # -------------------------------------------------------

  test "series are completely independent" do
    start_server([])

    for v <- 1..100, do: Percentile.record(:a, v)
    for v <- 200..209, do: Percentile.record(:b, v)

    assert {:ok, 50} = Percentile.query(:a, 0.50)
    assert {:ok, 200} = Percentile.query(:b, 0.0)
    assert {:ok, 209} = Percentile.query(:b, 1.0)

    Percentile.reset(:a)
    assert {:error, :empty} = Percentile.query(:a, 0.5)
    # b untouched
    assert {:ok, 209} = Percentile.query(:b, 1.0)
  end

  # -------------------------------------------------------
  # Count-based window
  # -------------------------------------------------------

  test "count-based window keeps only the most recent samples" do
    start_server(max_samples: 5)

    for v <- 1..10, do: Percentile.record(:c, v)

    # only [6,7,8,9,10] remain
    assert {:ok, 6} = Percentile.query(:c, 0.0)
    assert {:ok, 10} = Percentile.query(:c, 1.0)
    # ceil(0.5*5) = 3 -> s_3 = 8
    assert {:ok, 8} = Percentile.query(:c, 0.50)
  end

  test "count-based window drops oldest first" do
    start_server(max_samples: 3)

    Percentile.record(:c, 1)
    Percentile.record(:c, 2)
    Percentile.record(:c, 3)
    assert {:ok, 1} = Percentile.query(:c, 0.0)

    Percentile.record(:c, 4)
    # 1 dropped, window is [2,3,4]
    assert {:ok, 2} = Percentile.query(:c, 0.0)
    assert {:ok, 4} = Percentile.query(:c, 1.0)
  end

  # -------------------------------------------------------
  # Time-based window
  # -------------------------------------------------------

  test "time-based window keeps live samples and expires old ones" do
    start_server(window_ms: 1_000)

    # t=0
    Percentile.record(:t, 100)

    # t=500
    Clock.advance(500)
    Percentile.record(:t, 200)

    # t=900: both still live (ages 900 and 400 < 1000)
    Clock.advance(400)
    assert {:ok, 100} = Percentile.query(:t, 0.0)
    assert {:ok, 200} = Percentile.query(:t, 1.0)

    # t=1100: sample@0 age 1100 >= 1000 -> expired; sample@500 age 600 live
    Clock.advance(200)
    assert {:ok, 200} = Percentile.query(:t, 0.0)
    assert {:ok, 200} = Percentile.query(:t, 1.0)
  end

  test "sample expires exactly at the window boundary" do
    start_server(window_ms: 1_000)

    Percentile.record(:t, 42)

    # t=999: age 999 < 1000 -> still live
    Clock.advance(999)
    assert {:ok, 42} = Percentile.query(:t, 0.5)

    # t=1000: age 1000 >= 1000 -> expired
    Clock.advance(1)
    assert {:error, :empty} = Percentile.query(:t, 0.5)
  end

  test "expired samples do not contribute to the percentile rank" do
    start_server(window_ms: 1_000)

    # Record 1..50 at t=0
    for v <- 1..50, do: Percentile.record(:t, v)

    # t=1000: all of the above are expired
    Clock.advance(1_000)

    # Record 60..69 at t=1000
    for v <- 60..69, do: Percentile.record(:t, v)

    # Only the 10 fresh samples [60..69] count now
    assert {:ok, 60} = Percentile.query(:t, 0.0)
    assert {:ok, 69} = Percentile.query(:t, 1.0)
    # ceil(0.5*10) = 5 -> s_5 = 64
    assert {:ok, 64} = Percentile.query(:t, 0.50)
  end

  test "all samples expiring reports empty" do
    start_server(window_ms: 500)

    for v <- 1..20, do: Percentile.record(:t, v)
    assert {:ok, _} = Percentile.query(:t, 0.5)

    Clock.advance(500)
    assert {:error, :empty} = Percentile.query(:t, 0.5)
  end

  # -------------------------------------------------------
  # Both windows supplied together: both constraints apply
  # -------------------------------------------------------

  test "count limit still applies when a time window is also configured" do
    # TODO
  end

  test "time expiry still applies when a count window is also configured" do
    start_server(window_ms: 1_000, max_samples: 100)

    # Far fewer samples than max_samples, so only the time window can remove
    # them; once they age past the window the series must report empty.
    for v <- 1..3, do: Percentile.record(:both, v)
    assert {:ok, 1} = Percentile.query(:both, 0.0)
    assert {:ok, 3} = Percentile.query(:both, 1.0)

    Clock.advance(1_000)
    assert {:error, :empty} = Percentile.query(:both, 0.5)
  end

  test "both windows constrain the same series simultaneously" do
    start_server(window_ms: 1_000, max_samples: 3)

    # t=0: four samples arrive, count window drops 10 -> live [20, 30, 40]
    for v <- [10, 20, 30, 40], do: Percentile.record(:both, v)
    assert {:ok, 20} = Percentile.query(:both, 0.0)
    assert {:ok, 40} = Percentile.query(:both, 1.0)

    # t=600: 50 arrives, count window drops the oldest -> live [30, 40, 50]
    Clock.advance(600)
    Percentile.record(:both, 50)
    assert {:ok, 30} = Percentile.query(:both, 0.0)
    assert {:ok, 50} = Percentile.query(:both, 1.0)

    # t=1100: the t=0 samples (30, 40) are 1100ms old and expire; 50 (age 600)
    # is the only live sample, so it is both the min and the max.
    Clock.advance(500)
    assert {:ok, 50} = Percentile.query(:both, 0.0)
    assert {:ok, 50} = Percentile.query(:both, 0.50)
    assert {:ok, 50} = Percentile.query(:both, 1.0)
  end
end
```
