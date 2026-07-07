# Fill in the middle: `MultiSeriesResampler.resample/3`

Implement the public `resample/3` function for the `MultiSeriesResampler` module
below. Every other function in the module — including all the private helpers
(`build_row/6`, `empty_last/1`, `floor_bucket/2`, `aggregate/2`, `fetch_opt!/4`)
— is already written for you; your job is to fill in the body (all clauses) of
`resample/3` so that it drives those helpers correctly.

`resample/3` takes `series` (a map of `%{series_name => [{timestamp_ms, value}]}`),
`interval_ms` (a positive integer bucket width), and `opts` (a keyword list), and
returns a list of `{bucket_start_ms, %{series_name => aggregated_value}}` tuples
sorted ascending by bucket start. It must:

1. Provide a default of `[]` for `opts` (a multi-head declaration with a default
   argument).

2. In the main clause — guarded by `is_map(series) and is_integer(interval_ms)
   and interval_ms > 0`:
   - Read and validate the options with `fetch_opt!/4`: `:agg` (default `:last`,
     validated against `@valid_agg`) and `:fill` (default `:nil`, validated
     against `@valid_fill`).
   - Sort each series' points ascending by timestamp (build a new map with
     `Map.new/2`, sorting each list by `elem(&1, 0)`).
   - Collect every timestamp across all sorted series. If there are none (empty
     input map, or all series are empty lists), return `[]`.
   - Otherwise compute the grid: the first bucket is the earliest timestamp
     floored to an `interval_ms` boundary via `floor_bucket/2`, and the last
     bucket is `floor_bucket/2` of the latest timestamp. The series names are the
     keys of the sorted map.
   - Group each series' points by bucket start (`Enum.group_by/2` keyed by
     `floor_bucket(ts, interval_ms)`), producing a map of
     `%{series_name => %{bucket_start => points}}`.
   - Enumerate every bucket start from `first_bucket` to `last_bucket` inclusive,
     stepping by `interval_ms` (e.g. via `Stream.iterate/2` +
     `Stream.take_while/2`).
   - Fold left-to-right over the buckets with `Enum.map_reduce/3`, threading the
     per-series "most recent aggregated value" accumulator (seeded with
     `empty_last(names)`), calling `build_row/6` for each bucket. Return the list
     of rows produced (discard the final accumulator).

3. Provide the two error clauses that raise `ArgumentError` for a non-integer
   `interval_ms` and for a non-positive `interval_ms`, with the exact messages
   shown as `# TODO` placeholders — reproduce them in your solution.

Use only the Elixir standard library.

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
    # TODO
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
            :error     -> nil
          end

        filled =
          case {agg_value, fill} do
            {nil, :forward} -> Map.get(acc_last, name)
            {nil, :nil}     -> nil
            {v, _}          -> v
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