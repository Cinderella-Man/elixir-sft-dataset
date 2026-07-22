# Implement `resample/3` for `TimeSeriesResampler`

The module below is complete except for the body of the main
`resample/3` clause — the one guarded by
`when is_list(data) and is_integer(interval_ms) and interval_ms > 0`.
All other clauses (the default-args header, the empty-input clause, and the two
error-raising validation clauses) and every private helper are already provided.

Implement the body of that clause. It is the workhorse that turns an
irregularly-spaced list of `{timestamp_ms, value}` tuples into fixed-width
buckets. It must:

1. Resolve and validate the options. Read `:agg` (default `:last`) and `:fill`
   (default `:nil`) via the provided `fetch_opt!/4` helper, passing the
   `@valid_agg` and `@valid_fill` allow-lists so unsupported values raise
   `ArgumentError`.
2. Sort `data` ascending by timestamp (the first tuple element) so that
   `:first` / `:last` aggregations are well-defined.
3. Determine the bucket grid. Take the earliest and latest timestamps from the
   sorted list; compute the first and last bucket starts by flooring each to an
   `interval_ms` boundary with the `floor_bucket/2` helper.
4. Group the sorted points into their buckets, keyed by
   `floor_bucket(ts, interval_ms)` (use `Enum.group_by/2`).
5. Walk every bucket start from the first to the last inclusive, stepping by
   `interval_ms`, producing exactly one output tuple per bucket — no gaps. For
   each bucket:
   - If the bucket has points, aggregate them with `aggregate/2` using the
     resolved `agg` mode; otherwise its raw aggregated value is `nil`.
   - Apply gap filling: with `:nil`, an empty bucket emits `nil`; with
     `:forward`, an empty bucket carries forward the most recent non-empty
     bucket's aggregated value (still `nil` if no such bucket exists yet).
   - Thread the "last known aggregated value" through the walk so `:forward`
     works — update it only when the current bucket actually had data.
6. Return the list of `{bucket_start_ms, value}` tuples in ascending bucket
   order.

You may use `Stream.iterate/2` + `Stream.take_while/2` to generate the grid and
`Enum.map_reduce/3` to carry the forward-fill state, mirroring the helpers and
types already defined in the module.

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
    # TODO
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