defmodule CounterResamplerTest do
  use ExUnit.Case, async: false

  # Cumulative counter samples on a 1000ms grid:
  #   t=0    v=100
  #   t=300  v=110   (+10, bucket 0)
  #   t=800  v=150   (+40, bucket 0)
  #   t=1200 v=150   (+0,  bucket 1000)
  #   t=1700 v=300   (+150, bucket 1000)
  #   t=2500 v=50    reset! (detect -> +50, bucket 2000)
  @data [
    {0, 100},
    {300, 110},
    {800, 150},
    {1200, 150},
    {1700, 300},
    {2500, 50}
  ]
  @interval 1_000

  test ":delta sums per-bucket increments with reset detection" do
    result = CounterResampler.resample(@data, @interval, mode: :delta, reset: :detect)

    assert result == [{0, 50}, {1_000, 150}, {2_000, 50}]
  end

  test ":rate divides the increment by the interval in seconds" do
    result = CounterResampler.resample(@data, @interval, mode: :rate, reset: :detect)

    assert [{0, r0}, {1_000, r1}, {2_000, r2}] = result
    assert_in_delta r0, 50.0, 0.0001
    assert_in_delta r1, 150.0, 0.0001
    assert_in_delta r2, 50.0, 0.0001
  end

  test ":raw reset mode allows negative increments on a decrease" do
    result = CounterResampler.resample(@data, @interval, mode: :delta, reset: :raw)

    # last pair 300 -> 50 is -250, attributed to bucket 2000
    assert result == [{0, 50}, {1_000, 150}, {2_000, -250}]
  end

  test "empty buckets fill with zero in :delta mode" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)

    assert result == [{0, 50}, {1_000, 0}, {2_000, 250}]
  end

  test "empty buckets fill with nil when requested" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :nil)

    assert result == [{0, 50}, {1_000, nil}, {2_000, 250}]
  end

  test "empty buckets fill with 0.0 in :rate mode under :zero" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :rate, fill: :zero)

    assert [{0, _}, {1_000, gap}, {2_000, _}] = result
    assert gap === 0.0
  end

  test "the first bucket has no measured increase" do
    # single sample: one bucket, filled value (no predecessor)
    result = CounterResampler.resample([{300, 100}], @interval, mode: :delta, fill: :zero)
    assert result == [{0, 0}]

    nil_result = CounterResampler.resample([{300, 100}], @interval, mode: :delta, fill: :nil)
    assert nil_result == [{0, nil}]
  end

  test "all samples in one bucket sum their increments" do
    data = [{100, 10}, {200, 25}, {300, 40}]
    result = CounterResampler.resample(data, @interval, mode: :delta)

    # increments +15 and +15 both land in bucket 0
    assert result == [{0, 30}]
  end

  test "unordered input is sorted internally" do
    ordered = CounterResampler.resample(@data, @interval, mode: :delta)
    shuffled = CounterResampler.resample(Enum.reverse(@data), @interval, mode: :delta)
    assert ordered == shuffled
  end

  test "empty input returns empty list" do
    assert CounterResampler.resample([], @interval, mode: :delta) == []
  end

  test "output covers every bucket between first and last, sorted" do
    data = [{0, 0}, {4_200, 100}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)
    buckets = Enum.map(result, fn {b, _} -> b end)

    assert buckets == [0, 1_000, 2_000, 3_000, 4_000]
    assert buckets == Enum.sort(buckets)
  end

  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, 0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, @interval, mode: :average)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, @interval, reset: :ignore)
    end
  end
end