# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `TimeSeriesResampler` that takes a list of `{timestamp, value}` tuples at irregular intervals and resamples them into fixed-interval buckets.

I need these functions in the public API:

- `TimeSeriesResampler.resample(data, interval_ms, opts)` — the main entry point. `data` is a list of `{timestamp_ms, value}` tuples (integers and numbers). `interval_ms` is the bucket width in milliseconds. `opts` is a keyword list. Returns a list of `{bucket_start_ms, aggregated_value}` tuples sorted ascending by bucket start.

The options are:
- `:agg` — the aggregation mode, one of `:last`, `:first`, `:mean`, `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
- `:fill` — how to handle buckets with no data points. Either `:nil` (emit `{bucket_start, nil}`) or `:forward` (carry the last known aggregated value forward). Defaults to `:nil`.

Bucketing rules:
- The first bucket starts at the timestamp of the earliest data point, floored to the nearest `interval_ms` boundary (i.e. `floor(min_ts / interval_ms) * interval_ms`).
- The last bucket is the one that contains the latest data point.
- Every bucket between first and last must appear in the output, even if empty.
- A data point at timestamp `t` belongs to the bucket with start `floor(t / interval_ms) * interval_ms`.

Aggregation rules per mode:
- `:last` — the value of the latest timestamp in the bucket.
- `:first` — the value of the earliest timestamp in the bucket.
- `:mean` — arithmetic mean of all values in the bucket (float).
- `:sum` — sum of all values.
- `:count` — number of data points in the bucket (integer).
- `:max` — maximum value.
- `:min` — minimum value.

Gap filling:
- `:nil` — empty buckets get `nil` as their value.
- `:forward` — empty buckets get the aggregated value of the most recent non-empty bucket to their left. If there is no such bucket (gap at the very start), use `nil`.

Edge cases to handle:
- Empty input list → return `[]`.
- Single data point → return a single bucket.
- All points in the same bucket → return one bucket.
- Input may be given in any order; sort internally before processing.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.

## The buggy module

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
      [{0, 1.5}, {200, nil}, {400, nil}, {600, 3.0}]
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
    |> elem(1)
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

## Failing test report

```
21 of 23 test(s) failed:

  * test :last picks the value with the highest timestamp in each bucket
      protocol Enumerable not implemented for Integer
      
      Got value:
      
          99
      

  * test :first picks the value with the lowest timestamp in each bucket
      protocol Enumerable not implemented for Integer
      
      Got value:
      
          99
      

  * test :sum adds all values in each bucket
      protocol Enumerable not implemented for Integer
      
      Got value:
      
          99
      

  * test :count returns the number of points in each bucket
      protocol Enumerable not implemented for Integer
      
      Got value:
      
          1
      

  (…17 more)
```
