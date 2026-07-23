# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

# Time-Decay Weighted Rolling Percentile

Write me an Elixir GenServer module called `DecayPercentile` that computes
percentiles over samples whose influence **fades continuously with age** rather
than dropping off a hard window edge. A single running process manages many
independent **series**, each identified by an arbitrary `name` term.

Instead of a live/expired boolean, every sample carries an exponentially-decaying
weight based on how long ago it was recorded. Recent samples dominate; old
samples still count, but progressively less. This gives smooth, drift-aware
percentiles with no abrupt jumps when a sample crosses a boundary.

## Public API

- `DecayPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — name to register under. Default: `DecayPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. All ages are
    computed from this clock.
  - `:half_life_ms` — **required** positive integer. A sample of age `a` has
    weight `0.5 ^ (a / half_life_ms)` (weight `1.0` when just recorded, `0.5` at
    one half-life, `0.25` at two, and so on). Anything else raises `ArgumentError`.
  - `:max_samples` — optional positive integer bounding retained samples per
    series (oldest dropped first) so memory stays bounded.

- The `name` argument of `record/2`, `query/2`, `total_weight/1`, and `reset/1` is purely the **series** name — these helpers always call the server registered under the default `DecayPercentile` name (the `:name` start option changes process registration only, not how the helpers address the server).
- `DecayPercentile.record(name, value)` — records a numeric `value`, timestamped
  with the current clock time. Returns `:ok`.

- `DecayPercentile.query(name, percentile)` — computes the **weighted nearest-rank**
  percentile over the current samples of series `name`. `percentile` is a float in
  `0.0..1.0`. Returns `{:ok, value}` where `value` is one of the recorded samples,
  or `{:error, :empty}` when the series has no samples (or all weights have
  underflowed to zero). A sample whose weight has underflowed to zero is
  excluded from selection entirely — it can never be the returned value, at
  any percentile.

- `DecayPercentile.total_weight(name)` — returns `{:ok, w}` where `w` is the sum
  of the current decayed weights (a float), or `{:error, :empty}` under the same
  emptiness rule as `query` (no samples, or every weight underflowed to zero —
  never `{:ok, 0.0}`). Useful as an "effective sample count" for inspection.

- `DecayPercentile.reset(name)` — discards all samples for series `name`.
  Returns `:ok`.

## Weighted nearest-rank definition

At query time compute each sample's weight `w_i = 0.5 ^ ((now - t_i)/half_life_ms)`.
Sort the samples ascending by **value** as `(v_1, w_1), …, (v_n, w_n)` and let
`W = Σ w_i`. For a percentile `p`, walk the sorted list accumulating weight and
return the value `v_j` at the first position where the cumulative weight reaches
`p * W`:

```
target = p * W
return the first v_j where (w_1 + … + w_j) >= target
```

Consequences:
- `p = 0.0` returns the minimum-valued sample; `p = 1.0` returns the maximum.
- Doubling a sample's freshness (halving its age relative to others) can move the
  reported percentile toward that sample's value.
- **Uniform aging is neutral**: if no new samples arrive, advancing the clock
  scales every weight by the same factor, so the reported percentile is unchanged.

## Semantics

- Series are fully independent.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies. `:math.pow/2` is fine for the decay factor.
