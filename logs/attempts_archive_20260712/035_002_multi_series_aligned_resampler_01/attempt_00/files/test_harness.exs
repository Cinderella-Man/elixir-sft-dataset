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

  defp row(result, bucket) do
    {^bucket, map} = Enum.find(result, fn {b, _} -> b == bucket end)
    map
  end

  test ":sum aggregates each series independently per bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: :nil)

    assert row(result, 0) == %{cpu: 30, mem: 1}
    assert row(result, 2_000) == %{cpu: 20, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end

  test ":last picks per-series latest value in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :nil)

    assert row(result, 0) == %{cpu: 20, mem: 1}
    assert row(result, 2_000) == %{cpu: 15, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end

  test ":count counts per-series points in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :count, fill: :nil)

    assert row(result, 0) == %{cpu: 2, mem: 1}
    assert row(result, 2_000) == %{cpu: 2, mem: 1}
    assert row(result, 8_000) == %{cpu: 1, mem: 1}
  end

  test ":mean produces per-series floats" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :mean, fill: :nil)

    m0 = row(result, 0)
    assert_in_delta m0.cpu, 15.0, 0.001
    assert_in_delta m0.mem, 1.0, 0.001

    m2 = row(result, 2_000)
    assert_in_delta m2.cpu, 10.0, 0.001
    assert_in_delta m2.mem, 2.0, 0.001
  end

  test "fill: :nil leaves each series nil in empty buckets" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :nil)

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
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :nil)
    buckets = Enum.map(result, fn {b, _} -> b end)

    assert buckets == [0, 2_000, 4_000, 6_000, 8_000]
    assert buckets == Enum.sort(buckets)
  end

  test "every row's value map contains every series name" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: :nil)

    Enum.each(result, fn {_b, map} ->
      assert Map.has_key?(map, :cpu)
      assert Map.has_key?(map, :mem)
    end)
  end

  test "a present-but-empty series still appears in every row" do
    series = %{a: [], b: [{0, 5}, {2_500, 9}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: :nil)

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
end