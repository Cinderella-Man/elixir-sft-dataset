Implement the private `build_row/6` function.

It builds a single output row for one bucket of the shared grid. Its parameters are
`(names, grouped, bucket_start, agg, fill, last_values)`, where:

- `names` is the list of every series name present in the input.
- `grouped` is a map of `%{series_name => %{bucket_start => [datapoint]}}` — each series'
  points already grouped by their bucket start.
- `bucket_start` is the integer start timestamp of the bucket being built.
- `agg` is the aggregation mode to apply to every series.
- `fill` is the per-series gap-filling mode (`:nil` or `:forward`).
- `last_values` is a map of `%{series_name => most_recent_aggregated_value_or_nil}` carried
  in from the previous bucket, used for forward filling.

It must fold over `names`, and for each series:

- Look up that series' points for `bucket_start` in `grouped[name]`. If points exist,
  aggregate them with `aggregate/2` using `agg` to get the series' value for this bucket;
  otherwise the aggregated value is `nil`.
- Decide the value that actually goes into the row: if the aggregated value is `nil` and
  `fill` is `:forward`, use that series' most recent value from the accumulated
  last-values map (which is `nil` if the series has had no value yet); if the aggregated
  value is `nil` and `fill` is `:nil`, use `nil`; otherwise use the aggregated value.
- Update the running last-values map: when the aggregated value is non-`nil`, record it as
  that series' most recent value; otherwise leave the series' last value unchanged (so a
  forward-fill only carries genuine values, never filled placeholders).

The function returns `{{bucket_start, row}, next_last}`, where `row` is the
`%{series_name => value}` map for this bucket (every series name present) and `next_last`
is the updated last-values map to thread into the next bucket. This shape matches the
`Enum.map_reduce/3` call in `resample/3`.

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
  @type value       :: number()
  @type datapoint   :: {integer(), value()}
  @type agg_mode    :: :last | :first | :mean | :sum | :count | :max | :min
  @type fill_mode   :: :nil | :forward

  @valid_agg  [:last, :first, :mean, :sum, :count, :max, :min]
  @valid_fill [:nil, :forward]

  @doc """
  Resamples `series` onto a shared fixed-interval grid of width `interval_ms`.

  `series` is a map of `%{series_name => [{timestamp_ms, value}]}`. Returns a
  list of `{bucket_start_ms, %{series_name => aggregated_value}}` tuples sorted
  ascending by bucket start, with every series name present in every row.

  Options:

    * `:agg` — aggregation mode, one of #{inspect(@valid_agg)} (default `:last`).
    * `:fill` — per-series gap handling, `:nil` or `:forward` (default `:nil`).

  Returns `[]` for an empty input map or a map whose series are all empty.
  """
  @spec resample(%{optional(series_name()) => [datapoint()]}, pos_integer(), keyword()) ::
          [{integer(), %{optional(series_name()) => value() | nil}}]
  def resample(series, interval_ms, opts \\ [])

  def resample(series, interval_ms, opts)
      when is_map(series) and is_integer(interval_ms) and interval_ms > 0 do
    agg  = fetch_opt!(opts, :agg,  :last, @valid_agg)
    fill = fetch_opt!(opts, :fill, :nil,  @valid_fill)

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
        last_bucket  = floor_bucket(Enum.max(all_ts), interval_ms)
        names        = Map.keys(sorted)

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
    # TODO
  end

  defp empty_last(names), do: Map.new(names, &{&1, nil})

  defp floor_bucket(ts, interval_ms), do: div(ts, interval_ms) * interval_ms

  defp aggregate(points, :last),  do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum),   do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

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