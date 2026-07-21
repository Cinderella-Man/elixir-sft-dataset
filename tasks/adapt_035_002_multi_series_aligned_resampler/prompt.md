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

Write me an Elixir module called `MultiSeriesResampler` that takes **several named time
series** — each a list of `{timestamp, value}` tuples at irregular intervals — and
resamples them onto a **single shared fixed-interval grid**, aligning every series so that
each output row carries one aggregated value per series.

I need this public API:

- `MultiSeriesResampler.resample(series, interval_ms, opts)` — the main entry point.
  `series` is a map of `%{series_name => [{timestamp_ms, value}]}` (names are any term,
  usually atoms; timestamps are integers, values are numbers). `interval_ms` is the bucket
  width in milliseconds. `opts` is a keyword list. Returns a list of
  `{bucket_start_ms, %{series_name => aggregated_value}}` tuples sorted ascending by bucket
  start. **Every series name present in the input map appears in every row's value map**,
  even if that series has no data in that bucket.

The options are:
- `:agg` — the aggregation mode applied to every series, one of `:last`, `:first`, `:mean`,
  `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
- `:fill` — how to handle, **per series**, buckets with no data points for that series.
  Either `:nil` (put `nil` for that series in that row) or `:forward` (carry that series'
  most recent aggregated value forward). Defaults to `:nil`.

Bucketing rules:
- The grid spans **all** series jointly. The first bucket starts at the earliest timestamp
  across all series, floored to the nearest `interval_ms` boundary
  (`floor(min_ts / interval_ms) * interval_ms`). The last bucket is the one containing the
  latest timestamp across all series.
- Every bucket between first and last must appear in the output, even if all series are
  empty there.
- A data point at timestamp `t` belongs to the bucket with start
  `floor(t / interval_ms) * interval_ms`. This is floored division, so a boundary
  timestamp opens the next bucket (`t=2000` with `interval_ms=2000` → bucket `2000`, not
  `0`) and a negative timestamp lands at or below itself (`t=-1500` → bucket `-2000`).

Aggregation is computed **independently per series** within each bucket, using the same
rules as a single-series resampler:
- `:last` / `:first` — value at the latest / earliest timestamp in the bucket for that
  series (ordered by timestamp, not by input position).
- `:mean` — arithmetic mean of that series' values in the bucket, always a float (e.g. a
  mean of exactly twelve is `12.0`, not `12`).
- `:sum` — sum of that series' values.
- `:count` — number of that series' points in the bucket (integer).
- `:max` / `:min` — max / min of that series' values.

Gap filling is **per series**:
- `:nil` — a series with no points in a bucket gets `nil` for that bucket. This applies to
  every aggregation mode: an empty bucket under `:sum` or `:count` is `nil`, not `0`.
- `:forward` — a series with no points in a bucket gets its own most recent non-empty
  aggregated value. If that series has had no value yet (leading gap), use `nil`.

Edge cases to handle:
- Empty input map, or a map whose series are all empty lists → return `[]`.
- A series that is present but empty contributes no timestamps to the grid, yet still
  appears (as `nil` / forward-filled) in every row.
- Input for any series may be in any order; sort internally before processing.

Give me the complete module in a single file. Use only the Elixir standard library, no
external dependencies.

## Additional interface contract

- `resample/3` validates its arguments: an `interval_ms` that is not a positive integer
  (e.g. `0`, `-2000`, or `2_000.0`), or an `:agg`/`:fill` option value outside the
  documented sets (e.g. `agg: :median` or `fill: :backward`), raises an `ArgumentError`.
- This validation runs **before** the empty-input short-circuit: an invalid `:agg`/`:fill`
  still raises `ArgumentError` even when the input has no data points (an empty map like
  `%{}` or a map of all-empty series like `%{a: []}`), rather than returning `[]`.
