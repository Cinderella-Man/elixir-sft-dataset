# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `validate_positive` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# SLA Percentile Monitor with Inverse Queries

Write me an Elixir GenServer module called `RankPercentile` that maintains rolling
windows of numeric samples and answers questions in **both directions**: given a
percentile, what value? *and* given a value, what percentile / how many samples
exceed it? A single running process manages many independent **series**, each
identified by an arbitrary `name` term.

The inverse queries make this a latency/SLA monitor: `query/2` gives you the pXX
latency, `rank/2` gives you "what fraction of requests came in under X", and
`count_above/2` gives you the raw count of SLA violations.

## Public API

- `RankPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — name to register under. Default: `RankPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`.
  - `:window_ms` — positive integer enabling a **time-based** window. A sample
    recorded at time `t` is live while `now - t < window_ms`. Optional.
  - `:max_samples` — positive integer enabling a **count-based** window (most
    recent N samples retained per series, oldest dropped first). Optional.

  Both windows may be combined; both then apply.

- `RankPercentile.record(name, value)` — records a numeric `value`, timestamped
  with the current clock time. Returns `:ok`.

- `RankPercentile.query(name, percentile)` — the **forward** query. Computes the
  requested percentile over live samples using the **nearest-rank** method
  (`rank = max(1, ceil(p * n))`, return the value at that 1-indexed rank in
  ascending order). `percentile` is a float in `0.0..1.0`. Returns `{:ok, value}`
  (one of the recorded samples) or `{:error, :empty}`.

- `RankPercentile.rank(name, value)` — the **inverse** query. Returns
  `{:ok, q}` where `q` is the fraction of live samples less than or equal to
  `value` (the empirical CDF at `value`), a float in `0.0..1.0`, or
  `{:error, :empty}` when the series has no live samples. A `value` below the
  minimum yields `0.0`; a `value` at or above the maximum yields `1.0`.

- `RankPercentile.count_above(name, threshold)` — returns `{:ok, count}` where
  `count` is the number of live samples strictly greater than `threshold`.
  Returns `{:ok, 0}` for an empty or unknown series (never `:empty`).

- `RankPercentile.reset(name)` — discards all samples for series `name`.
  Returns `:ok`.

## Semantics

- Series are fully independent.
- Time-based expiration is applied at query time; expired samples contribute to
  none of `query/2`, `rank/2`, or `count_above/2`, nor to the count `n`.
- A fully expired or never-recorded series reports `{:error, :empty}` from
  `query/2` and `rank/2`, and `{:ok, 0}` from `count_above/2`.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies (a sorted list or similar is fine).

## The module with `validate_positive` missing

```elixir
defmodule RankPercentile do
  @moduledoc """
  A GenServer that maintains rolling windows of numeric samples across many
  independent series and answers percentile questions in both directions:

    * `query/2` — forward, nearest-rank percentile → value.
    * `rank/2` — inverse, value → empirical CDF (fraction at or below).
    * `count_above/2` — number of live samples strictly above a threshold.

  Time-based (`:window_ms`) and count-based (`:max_samples`) windows may be
  combined; all timestamps come from an injectable `:clock`.
  """

  use GenServer

  @default_name RankPercentile

  ## Public API

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Records `value` into the SLA percentile monitor for `name`. Returns `:ok`."
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @spec query(term, float) :: {:ok, number} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @spec rank(term, number) :: {:ok, float} | {:error, :empty}
  def rank(name, value) when is_number(value) do
    GenServer.call(@default_name, {:rank, name, value})
  end

  @spec count_above(term, number) :: {:ok, non_neg_integer}
  def count_above(name, threshold) when is_number(threshold) do
    GenServer.call(@default_name, {:count_above, name, threshold})
  end

  @spec reset(term) :: :ok
  def reset(name), do: GenServer.call(@default_name, {:reset, name})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = validate_positive(Keyword.get(opts, :window_ms))
    max_samples = validate_positive(Keyword.get(opts, :max_samples))

    {:ok,
     %{
       clock: clock,
       window_ms: window_ms,
       max_samples: max_samples,
       series: %{}
     }}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    sorted = live_values(state, name)
    {:reply, percentile_of(sorted, percentile), state}
  end

  def handle_call({:rank, name, value}, _from, state) do
    sorted = live_values(state, name)

    result =
      case sorted do
        [] -> {:error, :empty}
        _ -> {:ok, Enum.count(sorted, &(&1 <= value)) / length(sorted)}
      end

    {:reply, result, state}
  end

  def handle_call({:count_above, name, threshold}, _from, state) do
    count = state |> live_values(name) |> Enum.count(&(&1 > threshold))
    {:reply, {:ok, count}, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp live_values(state, name) do
    now = state.clock.()

    state.series
    |> Map.get(name, [])
    |> live_samples(now, state.window_ms)
    |> Enum.map(fn {_t, v} -> v end)
    |> Enum.sort()
  end

  defp percentile_of([], _percentile), do: {:error, :empty}

  defp percentile_of(sorted, percentile) do
    n = length(sorted)
    rank = max(1, ceil(percentile * n))
    {:ok, Enum.at(sorted, rank - 1)}
  end

  defp enforce_max(samples, nil), do: samples
  defp enforce_max(samples, max), do: Enum.take(samples, max)

  defp live_samples(samples, _now, nil), do: samples

  defp live_samples(samples, now, window_ms) do
    Enum.filter(samples, fn {t, _v} -> now - t < window_ms end)
  end

  defp validate_positive(nil) do
    # TODO
  end
end
```

Reply with `validate_positive` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
