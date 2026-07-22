defmodule MultiSeriesResampler do
  @moduledoc """
  Resamples several named, irregularly-sampled time series onto a single shared
  fixed-interval grid.

  Each input series is a list of `{timestamp_ms, value}` tuples. All series are aligned onto
  one common grid of buckets of width `interval_ms`, spanning from the earliest timestamp
  across all series (floored to an interval boundary) through the bucket containing the
  latest timestamp across all series.

  The output is a list of `{bucket_start_ms, %{series_name => aggregated_value}}` tuples,
  sorted ascending by bucket start. Every series name present in the input map appears in
  every row's value map, even when that series has no data in that bucket (in which case the
  `:fill` strategy decides the value).

  ## Options

    * `:agg` — aggregation mode applied to every series. One of `:last`, `:first`, `:mean`,
      `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
    * `:fill` — how to handle, per series, buckets that hold no points for that series.
      Either `:nil` (emit `nil`) or `:forward` (carry that series' most recent aggregated
      value forward; `nil` while the series has produced no value yet). Defaults to `:nil`.

  ## Examples

      iex> series = %{a: [{0, 1}, {1500, 3}], b: [{1200, 10}]}
      iex> MultiSeriesResampler.resample(series, 1000, agg: :last)
      [{0, %{a: 1, b: nil}}, {1000, %{a: 3, b: 10}}]

      iex> series = %{a: [{0, 1}], b: [{2500, 7}]}
      iex> MultiSeriesResampler.resample(series, 1000, fill: :forward)
      [{0, %{a: 1, b: nil}}, {1000, %{a: 1, b: nil}}, {2000, %{a: 1, b: 7}}]
  """

  @aggs [:last, :first, :mean, :sum, :count, :max, :min]
  @fills [nil, :forward]

  @type timestamp :: integer()
  @type value :: number()
  @type series_name :: term()
  @type series_map :: %{optional(series_name()) => [{timestamp(), value()}]}
  @type row :: {timestamp(), %{optional(series_name()) => value() | nil}}

  @doc """
  Resamples `series` onto a shared grid of `interval_ms`-wide buckets.

  `series` is a map of `%{series_name => [{timestamp_ms, value}]}`. Points within each series
  may be in any order; they are sorted internally.

  Returns a list of `{bucket_start_ms, %{series_name => aggregated_value}}` tuples sorted
  ascending by bucket start. Returns `[]` when the input map is empty or when every series is
  an empty list.

  Supported options are `:agg` (default `:last`) and `:fill` (default `:nil`); see the module
  documentation.

  Raises `ArgumentError` if `interval_ms` is not a positive integer, or if `:agg` / `:fill`
  is given an unsupported value.
  """
  @spec resample(series_map(), pos_integer(), keyword()) :: [row()]
  def resample(series, interval_ms, opts \\ []) when is_map(series) and is_list(opts) do
    validate_interval!(interval_ms)
    agg = validate_agg!(Keyword.get(opts, :agg, :last))
    fill = validate_fill!(Keyword.get(opts, :fill, nil))

    names = Map.keys(series)
    sorted = Map.new(series, fn {name, points} -> {name, Enum.sort_by(points, &elem(&1, 0))} end)

    case grid_bounds(sorted, interval_ms) do
      :empty ->
        []

      {first_bucket, last_bucket} ->
        buckets = bucketize(sorted, interval_ms, agg)

        first_bucket
        |> Stream.iterate(&(&1 + interval_ms))
        |> Enum.take(div(last_bucket - first_bucket, interval_ms) + 1)
        |> build_rows(buckets, names, fill)
    end
  end

  # -- validation ------------------------------------------------------------

  defp validate_interval!(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    :ok
  end

  defp validate_interval!(interval_ms) do
    raise ArgumentError,
          "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  defp validate_agg!(agg) when agg in @aggs, do: agg

  defp validate_agg!(agg) do
    raise ArgumentError,
          "invalid :agg #{inspect(agg)}, expected one of #{inspect(@aggs)}"
  end

  defp validate_fill!(fill) when fill in @fills, do: fill

  defp validate_fill!(fill) do
    raise ArgumentError,
          "invalid :fill #{inspect(fill)}, expected one of #{inspect(@fills)}"
  end

  # -- grid ------------------------------------------------------------------

  defp grid_bounds(sorted, interval_ms) do
    timestamps =
      sorted
      |> Map.values()
      |> Enum.reject(&(&1 == []))
      |> Enum.flat_map(fn points ->
        [{min_ts, _} | _] = points
        {max_ts, _} = List.last(points)
        [min_ts, max_ts]
      end)

    case timestamps do
      [] ->
        :empty

      timestamps ->
        min_ts = Enum.min(timestamps)
        max_ts = Enum.max(timestamps)
        {bucket_start(min_ts, interval_ms), bucket_start(max_ts, interval_ms)}
    end
  end

  defp bucket_start(timestamp, interval_ms) do
    Integer.floor_div(timestamp, interval_ms) * interval_ms
  end

  # Builds %{series_name => %{bucket_start => aggregated_value}} for non-empty buckets only.
  defp bucketize(sorted, interval_ms, agg) do
    Map.new(sorted, fn {name, points} ->
      grouped =
        points
        |> Enum.group_by(fn {ts, _value} -> bucket_start(ts, interval_ms) end)
        |> Map.new(fn {bucket, bucket_points} -> {bucket, aggregate(bucket_points, agg)} end)

      {name, grouped}
    end)
  end

  # -- aggregation -----------------------------------------------------------

  # `points` is non-empty and already sorted ascending by timestamp.
  defp aggregate(points, :last) do
    {_ts, value} = List.last(points)
    value
  end

  defp aggregate([{_ts, value} | _rest], :first), do: value

  defp aggregate(points, :mean) do
    values = values(points)
    Enum.sum(values) / length(values)
  end

  defp aggregate(points, :sum), do: points |> values() |> Enum.sum()
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :max), do: points |> values() |> Enum.max()
  defp aggregate(points, :min), do: points |> values() |> Enum.min()

  defp values(points), do: Enum.map(points, fn {_ts, value} -> value end)

  # -- row assembly ----------------------------------------------------------

  defp build_rows(bucket_starts, buckets, names, fill) do
    initial = Map.new(names, fn name -> {name, nil} end)

    {rows, _last_seen} =
      Enum.map_reduce(bucket_starts, initial, fn bucket, last_seen ->
        {row_values, next_seen} = row_for(bucket, buckets, names, fill, last_seen)
        {{bucket, row_values}, next_seen}
      end)

    rows
  end

  defp row_for(bucket, buckets, names, fill, last_seen) do
    Enum.reduce(names, {%{}, last_seen}, fn name, {row_values, seen} ->
      case buckets |> Map.fetch!(name) |> Map.fetch(bucket) do
        {:ok, value} ->
          {Map.put(row_values, name, value), Map.put(seen, name, value)}

        :error ->
          filled = if fill == :forward, do: Map.fetch!(seen, name), else: nil
          {Map.put(row_values, name, filled), seen}
      end
    end)
  end
end