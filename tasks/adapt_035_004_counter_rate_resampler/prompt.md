# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule TimeSeriesResampler do
  @moduledoc """
  Resamples a list of `{timestamp_ms, value}` tuples at irregular intervals
  into fixed-width time buckets with configurable aggregation and gap-filling.

  ## Bucketing

  Given an `interval_ms` width, every timestamp `t` is assigned to the bucket
  whose start is `floor(t / interval_ms) * interval_ms`.  The flooring is a
  true mathematical floor, so negative timestamps round *downwards* (away from
  zero) rather than being truncated towards zero.  The output covers every
  bucket from the one containing the earliest point to the one containing the
  latest point, inclusive, with no gaps.

  ## Options

  - `:agg`  – aggregation function: `:last` (default), `:first`, `:mean`,
               `:sum`, `:count`, `:max`, `:min`.
  - `:fill` – gap-filling strategy: `:nil` (default) or `:forward`.

  ## Example

      iex> data = [{100, 1.0}, {250, 2.0}, {600, 3.0}]
      iex> TimeSeriesResampler.resample(data, 200, agg: :mean, fill: :nil)
      [{0, 1.0}, {200, 2.0}, {400, nil}, {600, 3.0}]
  """

  @type timestamp_ms :: integer()
  @type value :: number()
  @type datapoint :: {timestamp_ms(), value()}
  @type bucket :: {timestamp_ms(), value() | nil}
  @type agg_mode :: :last | :first | :mean | :sum | :count | :max | :min
  @type fill_mode :: nil | :forward

  @valid_agg [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [nil, :forward]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Resample `data` into fixed `interval_ms` buckets.

  Returns a list of `{bucket_start_ms, aggregated_value}` tuples sorted
  ascending by bucket start.  Returns `[]` when `data` is empty.

  ## Parameters

  - `data`        – list of `{timestamp_ms, value}` tuples (any order).
  - `interval_ms` – positive integer bucket width in milliseconds.
  - `opts`        – keyword list; see module docs for supported keys.

  ## Raises

  - `ArgumentError` when `interval_ms` is not a positive integer, or when
    `:agg` / `:fill` receive an unsupported value.
  """
  @spec resample([datapoint()], pos_integer(), keyword()) :: [bucket()]
  def resample(data, interval_ms, opts \\ [])

  def resample([], _interval_ms, _opts), do: []

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    agg = fetch_opt!(opts, :agg, :last, @valid_agg)
    fill = fetch_opt!(opts, :fill, nil, @valid_fill)

    # 1. Sort ascending by timestamp so :first/:last are well-defined.
    sorted = Enum.sort_by(data, &elem(&1, 0))

    # 2. Determine the bucket grid.
    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    # 3. Group data points into their buckets.
    grouped =
      Enum.group_by(sorted, fn {ts, _v} -> floor_bucket(ts, interval_ms) end)

    # 4. Walk every bucket in order, aggregate, then fill gaps.
    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map_reduce(nil, fn bucket_start, last_value ->
      agg_value =
        case Map.fetch(grouped, bucket_start) do
          {:ok, points} -> aggregate(points, agg)
          :error -> nil
        end

      filled_value =
        case {agg_value, fill} do
          # carry forward (may still be nil)
          {nil, :forward} -> last_value
          {nil, nil} -> nil
          {v, _} -> v
        end

      next_last = if agg_value != nil, do: agg_value, else: last_value

      {{bucket_start, filled_value}, next_last}
    end)
    |> elem(0)
  end

  def resample(_data, interval_ms, _opts) when not is_integer(interval_ms) do
    raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  def resample(_data, interval_ms, _opts) when interval_ms <= 0 do
    raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Floor a timestamp to the nearest interval boundary.  `Integer.floor_div/2`
  # rounds towards negative infinity, unlike `div/2` which truncates towards
  # zero and would misplace negative timestamps.
  @spec floor_bucket(integer(), pos_integer()) :: integer()
  defp floor_bucket(ts, interval_ms) do
    Integer.floor_div(ts, interval_ms) * interval_ms
  end

  # Aggregate a non-empty list of sorted `{ts, value}` pairs.
  @spec aggregate([datapoint()], agg_mode()) :: value()
  defp aggregate(points, :last) do
    # Points are already sorted ascending; last element has the latest ts.
    points |> List.last() |> elem(1)
  end

  defp aggregate(points, :first) do
    points |> hd() |> elem(1)
  end

  defp aggregate(points, :count) do
    length(points)
  end

  defp aggregate(points, :sum) do
    Enum.reduce(points, 0, fn {_ts, v}, acc -> acc + v end)
  end

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_ts, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
  end

  defp aggregate(points, :max) do
    points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  end

  defp aggregate(points, :min) do
    points |> Enum.map(&elem(&1, 1)) |> Enum.min()
  end

  # Fetch a validated keyword option, returning the default when absent.
  @spec fetch_opt!(keyword(), atom(), term(), [term()]) :: term()
  defp fetch_opt!(opts, key, default, valid) do
    value = Keyword.get(opts, key, default)

    unless value in valid do
      raise ArgumentError,
            "invalid value #{inspect(value)} for option :#{key}; " <>
              "expected one of #{inspect(valid)}"
    end

    value
  end
end
```

## New specification

Write me an Elixir module called `CounterResampler` that resamples a stream of readings from
a **monotonically increasing counter** (think Prometheus-style counters: request totals,
bytes sent, etc.) into fixed-interval buckets of **per-interval increase or rate**, with
**counter-reset detection**. This is different from a plain aggregator: the values are
cumulative, so what matters is the *change* between consecutive samples, not the samples
themselves.

I need this public API:

- `CounterResampler.resample(data, interval_ms, opts)` — the main entry point. `data` is a
  list of `{timestamp_ms, counter_value}` tuples (integers and non-negative numbers) at
  irregular intervals. `interval_ms` is the bucket width in milliseconds. `opts` is a keyword
  list. Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending by
  bucket start.

The options are:
- `:mode` — `:delta` (default) emits the total counter increase attributed to the bucket;
  `:rate` emits that increase divided by the interval length in seconds
  (`interval_ms / 1000`), yielding a float per-second rate.
- `:reset` — `:detect` (default) or `:raw`. Controls how a decrease between two consecutive
  samples is interpreted (see below).
- `:fill` — `:zero` (default) or `:nil`. How to fill buckets that receive no measured
  increase.

Computation rules:
- Sort samples ascending by timestamp first (input may be unordered).
- Increases are computed between **consecutive samples**. For consecutive samples
  `(t0, v0)` then `(t1, v1)`, the increment is:
  - `:reset` = `:detect` → if `v1 >= v0`, the increment is `v1 - v0`; if `v1 < v0`, the
    counter is assumed to have reset, and the increment is taken to be `v1` (the value
    accumulated since the reset).
  - `:reset` = `:raw` → the increment is always `v1 - v0` (may be negative).
- Each consecutive increment is attributed to the bucket of the **later** sample `t1`
  (`floor(t1 / interval_ms) * interval_ms`).
- A bucket's value is the **sum** of all increments attributed to it. Because the very first
  sample has no predecessor, it contributes no increment (a bucket containing only the first
  sample and nothing else has no measured increase).

Bucketing rules:
- The first bucket starts at the earliest sample timestamp, floored to an `interval_ms`
  boundary. The last bucket is the one containing the latest sample. Every bucket in between
  appears in the output.
- For `:delta` mode, a bucket with no attributed increment is `0` under `:fill = :zero` or
  `nil` under `:fill = :nil`. For `:rate` mode, an empty bucket is `0.0` under `:zero` or
  `nil` under `:nil`.

Edge cases:
- Empty input → `[]`.
- A single sample → exactly one bucket whose value is the empty/`fill` value (no predecessor,
  so no measured increase).
- All samples in one bucket → one bucket summing the increments between them.

Give me the complete module in a single file. Use only the Elixir standard library, no
external dependencies.

## Additional interface contract

- `resample/3` validates its arguments: an `interval_ms` that is not a positive integer
  (e.g. `0`), or a `:mode`/`:reset`/`:fill` option value outside the documented sets
  (e.g. `mode: :average` or `reset: :ignore`), raises an `ArgumentError`.
