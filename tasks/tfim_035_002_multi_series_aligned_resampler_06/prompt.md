# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

  # Floored division, not truncation: a negative timestamp must land in the
  # bucket at or below it (floor(t / interval) * interval), matching the grid
  # rule for the earliest timestamp.
  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MultiSeriesResamplerTest do
  use ExUnit.Case, async: false

  # Two series aligned onto a 2000ms grid.
  #
  #   cpu: t=0→10, t=1500→20, t=3100→5, t=3800→15, t=8200→99
  #   mem: t=100→1, t=2500→2,  t=9000→7
  #
  # Joint grid: min_ts=0, max_ts=9000 → buckets 0,2000,4000,6000,8000
  #
  #   bucket 0    : cpu[10,20]  mem[1]
  #   bucket 2000 : cpu[5,15]   mem[2]
  #   bucket 4000 : cpu[]       mem[]
  #   bucket 6000 : cpu[]       mem[]
  #   bucket 8000 : cpu[99]     mem[7]
  @series %{
    cpu: [{0, 10}, {3100, 5}, {8200, 99}, {1500, 20}, {3800, 15}],
    mem: [{100, 1}, {9000, 7}, {2500, 2}]
  }
  @interval 2_000

  # Values chosen so that every aggregation mode yields a different row map:
  # the earliest, latest, smallest and largest value of a bucket are all
  # distinct once both series are read together.
  #
  #   bucket 0    : cpu[10, 90, 40] (in time order)  mem[8, 2]
  #   bucket 2000 : cpu[3, 1, 7]                     mem[6, 4]
  @spread %{
    cpu: [{1_500, 40}, {0, 10}, {2_500, 1}, {500, 90}, {3_900, 7}, {2_100, 3}],
    mem: [{1_900, 2}, {200, 8}, {3_100, 4}, {2_200, 6}]
  }

  defp row(result, bucket) do
    {^bucket, map} = Enum.find(result, fn {b, _} -> b == bucket end)
    map
  end

  test ":sum aggregates each series independently per bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: nil)

    assert row(result, 0) == %{cpu: 30, mem: 1}
    assert row(result, 2_000) == %{cpu: 20, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end

  test ":last picks per-series latest value in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: nil)

    assert row(result, 0) == %{cpu: 20, mem: 1}
    assert row(result, 2_000) == %{cpu: 15, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end

  test ":count counts per-series points in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :count, fill: nil)

    assert row(result, 0) == %{cpu: 2, mem: 1}
    assert row(result, 2_000) == %{cpu: 2, mem: 1}
    assert row(result, 8_000) == %{cpu: 1, mem: 1}
  end

  test ":mean produces per-series floats" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :mean, fill: nil)

    m0 = row(result, 0)
    assert_in_delta m0.cpu, 15.0, 0.001
    assert_in_delta m0.mem, 1.0, 0.001

    m2 = row(result, 2_000)
    assert_in_delta m2.cpu, 10.0, 0.001
    assert_in_delta m2.mem, 2.0, 0.001
  end

  test "fill: :nil leaves each series nil in empty buckets" do
    # TODO
  end

  test "fill: :forward carries each series' own last value forward" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :forward)

    # cpu last at bucket 2000 = 15, mem last at bucket 2000 = 2
    assert row(result, 4_000) == %{cpu: 15, mem: 2}
    assert row(result, 6_000) == %{cpu: 15, mem: 2}
    # Real data still present at 8000
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end

  test "every bucket in the joint range is present and sorted" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: nil)
    buckets = Enum.map(result, fn {b, _} -> b end)

    assert buckets == [0, 2_000, 4_000, 6_000, 8_000]
    assert buckets == Enum.sort(buckets)
  end

  test "every row's value map contains every series name" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: nil)

    Enum.each(result, fn {_b, map} ->
      assert Map.has_key?(map, :cpu)
      assert Map.has_key?(map, :mem)
    end)
  end

  test "a present-but-empty series still appears in every row" do
    series = %{a: [], b: [{0, 5}, {2_500, 9}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert row(result, 0) == %{a: nil, b: 5}
    assert row(result, 2_000) == %{a: nil, b: 9}
  end

  test "empty series only forward-fills after it first has a value" do
    # a has a leading gap: no data until bucket 2000
    series = %{a: [{2_500, 7}], b: [{0, 1}, {2_500, 2}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last, fill: :forward)

    # bucket 0: a has no value yet -> nil even under :forward
    assert row(result, 0) == %{a: nil, b: 1}
    assert row(result, 2_000) == %{a: 7, b: 2}
  end

  test "empty input map returns empty list" do
    assert MultiSeriesResampler.resample(%{}, @interval, agg: :sum) == []
  end

  test "map of all-empty series returns empty list" do
    assert MultiSeriesResampler.resample(%{a: [], b: []}, @interval, agg: :sum) == []
  end

  test "input order does not matter" do
    forward = MultiSeriesResampler.resample(@series, @interval, agg: :sum)

    reversed =
      Map.new(@series, fn {name, pts} -> {name, Enum.reverse(pts)} end)

    backward = MultiSeriesResampler.resample(reversed, @interval, agg: :sum)
    assert forward == backward
  end

  test "a negative timestamp floors to the bucket at or below it" do
    # floor(-1500 / 2000) * 2000 = -2000, not 0: truncating toward zero would
    # misplace the point AND shift the grid's first bucket.
    series = %{cpu: [{-1500, 4}, {500, 6}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert Enum.map(result, fn {bucket, _} -> bucket end) == [-2000, 0]
    assert row(result, -2_000) == %{cpu: 4}
    assert row(result, 0) == %{cpu: 6}
  end

  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, 0, agg: :sum)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, @interval, agg: :median)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, @interval, fill: :backward)
    end
  end

  test ":first picks per-series earliest value in the bucket" do
    # Earliest by timestamp, not smallest and not first in the input list:
    # cpu's bucket-0 points arrive out of order and its earliest value (10)
    # sits below its latest (40) and its largest (90).
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :first, fill: nil)

    assert row(result, 0) == %{cpu: 10, mem: 8}
    assert row(result, 2_000) == %{cpu: 3, mem: 6}
  end

  test ":max picks per-series largest value in the bucket" do
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :max, fill: nil)

    assert row(result, 0) == %{cpu: 90, mem: 8}
    assert row(result, 2_000) == %{cpu: 7, mem: 6}
  end

  test ":min picks per-series smallest value in the bucket" do
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :min, fill: nil)

    assert row(result, 0) == %{cpu: 10, mem: 2}
    assert row(result, 2_000) == %{cpu: 1, mem: 4}
  end

  test "omitting :agg aggregates with :last" do
    # cpu's bucket values in time order are 10, 90, 40, so :last (40) differs
    # from :first, :min, :max, :sum, :count and :mean.
    series = %{cpu: [{1_500, 40}, {0, 10}, {500, 90}], mem: [{200, 3}, {900, 8}]}
    result = MultiSeriesResampler.resample(series, @interval, fill: nil)

    assert result == [{0, %{cpu: 40, mem: 8}}]
  end

  test "omitting :fill leaves empty buckets nil" do
    # Bucket 2000 has no cpu points; forward filling would carry 5 into it.
    series = %{cpu: [{0, 5}, {4_500, 7}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last)

    assert result == [{0, %{cpu: 5}}, {2_000, %{cpu: nil}}, {4_000, %{cpu: 7}}]
  end

  test "both options omitted use :last aggregation and nil gap filling" do
    # cpu's bucket-0 values in time order are 10, 90, 40 and bucket 2000 is
    # empty: the defaults must yield 40 there and leave the gap nil.
    series = %{cpu: [{1_500, 40}, {0, 10}, {500, 90}, {4_200, 7}]}
    result = MultiSeriesResampler.resample(series, @interval, [])

    assert result == [{0, %{cpu: 40}}, {2_000, %{cpu: nil}}, {4_000, %{cpu: 7}}]
  end

  test "a non-integer or negative interval raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, 2_000.0, agg: :sum)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, -2_000, agg: :sum)
    end
  end

  test "a timestamp exactly on a boundary opens the next bucket" do
    # 1999 -> bucket 0, 2000 -> bucket 2000 (not 0), and the joint max at
    # exactly 4000 must still produce bucket 4000 as the last row.
    series = %{cpu: [{1_999, 2}, {2_000, 1}], mem: [{4_000, 3}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert result == [
             {0, %{cpu: 2, mem: nil}},
             {2_000, %{cpu: 1, mem: nil}},
             {4_000, %{cpu: nil, mem: 3}}
           ]
  end

  test ":mean yields a float even when the mean is a whole number" do
    # mem's mean is exactly 12; integer division or a rounding shortcut would
    # return 12 rather than the promised float.
    series = %{cpu: [{0, 1}, {500, 2}], mem: [{0, 10}, {500, 11}, {900, 15}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :mean, fill: nil)

    m0 = row(result, 0)
    assert m0.cpu === 1.5
    assert m0.mem === 12.0
  end

  test "an always-empty series stays nil in every row under fill: :forward" do
    series = %{a: [], b: [{0, 1}, {2_500, 2}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last, fill: :forward)

    assert result == [{0, %{a: nil, b: 1}}, {2_000, %{a: nil, b: 2}}]
  end

  test ":count and :sum leave empty buckets nil rather than zero" do
    series = %{cpu: [{0, 5}, {4_500, 7}], mem: [{0, 1}]}

    counted = MultiSeriesResampler.resample(series, @interval, agg: :count, fill: nil)
    assert row(counted, 2_000) == %{cpu: nil, mem: nil}
    assert row(counted, 4_000) == %{cpu: 1, mem: nil}

    summed = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)
    assert row(summed, 2_000) == %{cpu: nil, mem: nil}
    assert row(summed, 4_000) == %{cpu: 7, mem: nil}
  end

  test "options are validated even when the input has no data points" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(%{}, @interval, agg: :median)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(%{a: []}, @interval, fill: :backward)
    end
  end

  test ":max and :min differ from :first and :last within the same bucket" do
    # cpu's bucket-0 points in time order are 10, 90, 40: the largest (90) is
    # neither the earliest nor the latest, and the smallest (10) coincides with
    # the earliest only, so implementing :max as :last or :min as :first fails.
    maxed = MultiSeriesResampler.resample(@spread, @interval, agg: :max, fill: nil)
    minned = MultiSeriesResampler.resample(@spread, @interval, agg: :min, fill: nil)
    firsted = MultiSeriesResampler.resample(@spread, @interval, agg: :first, fill: nil)
    lasted = MultiSeriesResampler.resample(@spread, @interval, agg: :last, fill: nil)

    assert row(maxed, 0).cpu == 90
    assert row(minned, 0).cpu == 10
    assert row(firsted, 0).cpu == 10
    assert row(lasted, 0).cpu == 40

    # Bucket 2000 separates :min from :first and :max from :last as well.
    assert row(maxed, 2_000).cpu == 7
    assert row(minned, 2_000).cpu == 1
    assert row(firsted, 2_000).cpu == 3
    assert row(lasted, 2_000).cpu == 7
  end
end
```
