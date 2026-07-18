# Bring this working module up to house style

I asked for the following:

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
  `floor(t / interval_ms) * interval_ms`.

Aggregation is computed **independently per series** within each bucket, using the same
rules as a single-series resampler:
- `:last` / `:first` — value at the latest / earliest timestamp in the bucket for that series.
- `:mean` — arithmetic mean of that series' values in the bucket (float).
- `:sum` — sum of that series' values.
- `:count` — number of that series' points in the bucket (integer).
- `:max` / `:min` — max / min of that series' values.

Gap filling is **per series**:
- `:nil` — a series with no points in a bucket gets `nil` for that bucket.
- `:forward` — a series with no points in a bucket gets its own most recent non-empty
  aggregated value. If that series has had no value yet (leading gap), use `nil`.

Edge cases to handle:
- Empty input map, or a map whose series are all empty lists → return `[]`.
- A series that is present but empty contributes no timestamps to the grid, yet still
  appears (as `nil` / forward-filled) in every row.
- Input for any series may be in any order; sort internally before processing.

Give me the complete module in a single file. Use only the Elixir standard library, no
external dependencies.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

```elixir
defmodule MultiSeriesResampler do
  @moduledoc """
  Resamples several named `{timestamp_ms, value}` series onto a single shared
  fixed-interval grid, aligning them so each output row carries one aggregated
  value per series.

  The grid spans every series jointly: it starts at the earliest timestamp seen
  across all series (floored to an `interval_ms` boundary) and ends at the bucket
  containing the latest timestamp across all series. Every bucket in between is
  emitted. Aggregation and gap-filling are computed independently per series.
  """

  @type series_name :: term()
  @type value :: number()
  @type datapoint :: {integer(), value()}
  @type agg_mode :: :last | :first | :mean | :sum | :count | :max | :min
  @type fill_mode :: nil | :forward

  @valid_agg [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [nil, :forward]

  @spec resample(%{optional(series_name()) => [datapoint()]}, pos_integer(), keyword()) ::
          [{integer(), %{optional(series_name()) => value() | nil}}]
  def resample(series, interval_ms, opts \\ [])

  def resample(series, interval_ms, opts)
      when is_map(series) and is_integer(interval_ms) and interval_ms > 0 do
    agg = fetch_opt!(opts, :agg, :last, @valid_agg)
    fill = fetch_opt!(opts, :fill, nil, @valid_fill)

    sorted =
      Map.new(series, fn {name, points} ->
        {name, Enum.sort_by(points, &elem(&1, 0))}
      end)

    all_ts = for {_name, pts} <- sorted, {ts, _v} <- pts, do: ts

    case all_ts do
      [] ->
        []

      _ ->
        first_bucket = floor_bucket(Enum.min(all_ts), interval_ms)
        last_bucket = floor_bucket(Enum.max(all_ts), interval_ms)
        names = Map.keys(sorted)

        grouped =
          Map.new(sorted, fn {name, pts} ->
            {name, Enum.group_by(pts, fn {ts, _v} -> floor_bucket(ts, interval_ms) end)}
          end)

        buckets =
          first_bucket
          |> Stream.iterate(&(&1 + interval_ms))
          |> Stream.take_while(&(&1 <= last_bucket))
          |> Enum.to_list()

        {rows, _last} =
          Enum.map_reduce(buckets, empty_last(names), fn bucket_start, last_values ->
            build_row(names, grouped, bucket_start, agg, fill, last_values)
          end)

        rows
    end
  end

  def resample(series, interval_ms, _opts)
      when is_map(series) and not is_integer(interval_ms) do
    raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  def resample(series, interval_ms, _opts)
      when is_map(series) and interval_ms <= 0 do
    raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp build_row(names, grouped, bucket_start, agg, fill, last_values) do
    {row, next_last} =
      Enum.reduce(names, {%{}, last_values}, fn name, {acc_row, acc_last} ->
        agg_value =
          case Map.fetch(grouped[name], bucket_start) do
            {:ok, pts} -> aggregate(pts, agg)
            :error -> nil
          end

        filled =
          case {agg_value, fill} do
            {nil, :forward} -> Map.get(acc_last, name)
            {nil, nil} -> nil
            {v, _} -> v
          end

        new_last =
          if agg_value != nil,
            do: Map.put(acc_last, name, agg_value),
            else: acc_last

        {Map.put(acc_row, name, filled), new_last}
      end)

    {{bucket_start, row}, next_last}
  end

  defp empty_last(names), do: Map.new(names, &{&1, nil})

  defp floor_bucket(ts, interval_ms), do: div(ts, interval_ms) * interval_ms

  defp aggregate(points, :last), do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum), do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max), do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min), do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_t, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
  end

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

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/035_002_multi_series_aligned_resampler_01/attempt_0 -->
