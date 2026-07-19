# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

# Histogram-Based Approximate Rolling Percentile

Write me an Elixir GenServer module called `HistogramPercentile` that estimates
percentiles over a rolling time window using a **fixed bucket histogram** instead
of storing every raw sample. A single running process manages many independent
**series**, each identified by an arbitrary `name` term.

Unlike a sorted-list calculator, this variant trades exactness for **bounded
memory**: no matter how many samples arrive, a series only ever stores a small
grid of per-time-slice bucket counts.

## Public API

- `HistogramPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — the name to register under. Default: `HistogramPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. Every timestamp used
    for windowing must come from this function.
  - `:edges` — **required**. A strictly increasing list of at least two numbers
    `[e0, e1, …, ek]` defining `k` buckets. Bucket `i` covers `[e_i, e_{i+1})`,
    with the final bucket `[e_{k-1}, ek]` treated as closed. A recorded value below
    `e0` is clamped into bucket 0; a value at or above `ek` is clamped into the last
    bucket. Supplying anything else raises `ArgumentError` — and the raise comes
    **synchronously from `start_link/1` in the calling process**: validate the
    options eagerly before spawning the server, rather than raising inside
    `init/1`, which would turn the error into a linked-process exit instead of a
    catchable raise.
  - `:window_ms` — **required** positive integer. A sample recorded at time `t`
    contributes to queries while `now - t < window_ms`.
  - `:slots` — positive integer, default `60`. The window is divided into this many
    time slices; each series keeps one histogram per slice in a ring buffer. When a
    slice's slot is reused in a later cycle, its old counts are discarded. Slot
    reuse is **not** the only expiry: each slot must remember which time slice
    wrote it, because a query must exclude any slot whose slice has already aged
    out of the window — even when that slot has not been reused yet. Once
    `window_ms` passes with no new samples recorded, a query on that series
    returns `{:error, :empty}`.

- `HistogramPercentile.record(series, value)` — increments the bucket for `value`
  in the current time slice of series `series`. Returns `:ok`.

- `HistogramPercentile.query(series, percentile)` — returns `{:ok, estimate}` where
  `estimate` is a float, or `{:error, :empty}` when no live counts exist.
  `percentile` is a float in `0.0..1.0`.

- `HistogramPercentile.reset(series)` — discards all counts for series `series`.
  Returns `:ok`.

These three functions are always addressed to the singleton process registered
under the **default** `HistogramPercentile` name — their first argument is a
**series identifier** (an arbitrary term such as `:latency` or `:d`), never a
server reference or pid. Do not thread a server argument through the API.

## Estimation algorithm (histogram quantile)

At query time, sum the per-bucket counts across every stored slice whose start
time `s` satisfies `now - s < window_ms`, producing a list of counts
`c_0 … c_{k-1}` with total `n`. If `n == 0`, return `{:error, :empty}`. Otherwise
use Prometheus-style linear interpolation:

```
target = percentile * n
walk buckets in order, tracking cum_before (counts in earlier buckets);
pick the first bucket i where cum_before + c_i >= target (or the last bucket);
lo = e_i,  hi = e_{i+1},  frac = (target - cum_before) / c_i  (0 if c_i == 0)
estimate = lo + (hi - lo) * clamp(frac, 0.0, 1.0)
```

Consequences:
- `percentile = 0.0` returns `e0` (the low edge).
- `percentile = 1.0` returns `ek` (the high edge).
- Results are approximate; error is bounded by bucket width.

## Semantics

- Series are fully independent.
- Windowing is applied at query time, so advancing the clock and re-querying
  reflects newly-expired slices.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies.
