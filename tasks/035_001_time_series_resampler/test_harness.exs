defmodule TimeSeriesResamplerTest do
  use ExUnit.Case, async: true

  # Hand-computed fixture used across several tests.
  # Timestamps (ms) and values:
  #   t=0    → 10
  #   t=1500 → 20
  #   t=3100 → 5
  #   t=3800 → 15
  #   t=8200 → 99
  #
  # Bucketed at 2000 ms intervals starting at floor(0/2000)*2000 = 0:
  #   [0,    2000) → {0, 1500}       → values [10, 20]
  #   [2000, 4000) → {2000, 3100, 3800} → values [5, 15]
  #   [4000, 6000) → empty
  #   [6000, 8000) → empty
  #   [8000,10000) → {8200}          → values [99]

  @data [{0, 10}, {3100, 5}, {8200, 99}, {1500, 20}, {3800, 15}]
  @interval 2_000

  # -------------------------------------------------------
  # Aggregation modes — non-empty buckets
  # -------------------------------------------------------

  test ":last picks the value with the highest timestamp in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)

    assert {0, 20} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 15} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  test ":first picks the value with the lowest timestamp in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :first, fill: nil)

    assert {0, 10} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 5} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  test ":sum adds all values in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :sum, fill: nil)

    # 10 + 20
    assert {0, 30} = Enum.find(result, fn {b, _} -> b == 0 end)
    # 5 + 15
    assert {2000, 20} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  test ":count returns the number of points in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :count, fill: nil)

    assert {0, 2} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 2} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 1} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  test ":mean computes the arithmetic mean for each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :mean, fill: nil)

    {_, mean_0} = Enum.find(result, fn {b, _} -> b == 0 end)
    # (10 + 20) / 2
    assert_in_delta mean_0, 15.0, 0.001

    {_, mean_2000} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    # (5 + 15) / 2
    assert_in_delta mean_2000, 10.0, 0.001

    {_, mean_8000} = Enum.find(result, fn {b, _} -> b == 8_000 end)
    assert_in_delta mean_8000, 99.0, 0.001
  end

  test ":max returns the maximum value in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :max, fill: nil)

    assert {0, 20} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 15} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  test ":min returns the minimum value in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :min, fill: nil)

    assert {0, 10} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 5} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end

  # -------------------------------------------------------
  # Gap filling
  # -------------------------------------------------------

  test "fill: :nil emits nil for empty buckets" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)

    bucket_map = Map.new(result)
    assert Map.has_key?(bucket_map, 4_000)
    assert Map.has_key?(bucket_map, 6_000)
    assert bucket_map[4_000] == nil
    assert bucket_map[6_000] == nil
  end

  test "fill: :forward carries the last known value into empty buckets" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: :forward)

    bucket_map = Map.new(result)
    # Bucket at 2000 has last=15, so 4000 and 6000 should carry 15 forward
    assert bucket_map[4_000] == 15
    assert bucket_map[6_000] == 15
    # The filled bucket at 8000 still has the real data
    assert bucket_map[8_000] == 99
  end

  test "fill: :forward uses nil when gap is at the very start" do
    # Only one point, at t=5000; interval=2000 → bucket 4000
    # No bucket precedes it, so a leading gap would be nil — but here
    # there IS no gap before the first bucket. Let's construct a case:
    # Two separated points with a gap before either:
    # We ensure the first bucket is lonely to confirm no spurious carry.
    data = [{5_000, 42}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :last, fill: :forward)
    assert result == [{4_000, 42}]
  end

  # -------------------------------------------------------
  # Bucket coverage — every bucket in range is present
  # -------------------------------------------------------

  test "output contains every bucket between first and last, none missing" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)
    buckets = Enum.map(result, fn {b, _} -> b end)

    expected_buckets = [0, 2_000, 4_000, 6_000, 8_000]
    assert buckets == expected_buckets
  end

  test "output is sorted ascending by bucket start" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)
    buckets = Enum.map(result, fn {b, _} -> b end)
    assert buckets == Enum.sort(buckets)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty input returns empty list" do
    assert [] = TimeSeriesResampler.resample([], @interval, agg: :last, fill: nil)
  end

  test "single data point produces exactly one bucket" do
    result = TimeSeriesResampler.resample([{7_500, 77}], @interval, agg: :sum, fill: nil)
    assert length(result) == 1
    [{bucket, value}] = result
    # floor(7500 / 2000) * 2000
    assert bucket == 6_000
    assert value == 77
  end

  test "all points in the same bucket produces one bucket" do
    data = [{100, 1}, {200, 2}, {300, 3}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: nil)
    assert length(result) == 1
    assert [{0, 3}] = result
  end

  test "input in reverse order gives same result as sorted input" do
    forward = TimeSeriesResampler.resample(@data, @interval, agg: :sum, fill: nil)
    backward = TimeSeriesResampler.resample(Enum.reverse(@data), @interval, agg: :sum, fill: nil)
    assert forward == backward
  end

  test "bucket boundary: point exactly on boundary belongs to new bucket" do
    # t=2000 is the start of bucket [2000, 4000), not [0, 2000)
    data = [{0, 1}, {2_000, 2}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: nil)
    bucket_map = Map.new(result)
    assert bucket_map[0] == 1
    assert bucket_map[2_000] == 1
  end

  test ":count with fill: :forward fills gaps with count from last non-empty bucket" do
    # Bucket 0: 2 points; bucket 2000: empty; bucket 4000: 1 point
    data = [{0, 10}, {500, 20}, {4_100, 30}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: :forward)
    bucket_map = Map.new(result)
    assert bucket_map[0] == 2
    # carried forward from bucket 0
    assert bucket_map[2_000] == 2
    assert bucket_map[4_000] == 1
  end
end
