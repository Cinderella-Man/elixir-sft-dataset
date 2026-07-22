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
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: nil)

    assert row(result, 4_000) == %{cpu: nil, mem: nil}
    assert row(result, 6_000) == %{cpu: nil, mem: nil}
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
