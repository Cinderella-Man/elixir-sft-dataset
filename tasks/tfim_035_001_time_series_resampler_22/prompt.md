# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
    agg = fetch_opt!(opts, :agg, :last, @valid_agg)
    fill = fetch_opt!(opts, :fill, nil, @valid_fill)

    # 1. Sort ascending by timestamp so :first/:last are well-defined.
    sorted = Enum.sort_by(data, &elem(&1, 0))

    # 2. Determine the bucket grid.
    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    # 3. Group data points into their buckets.
    grouped =
      Enum.group_by(sorted, fn {ts, _v} -> floor_bucket(ts, interval_ms) end)

    # 4. Walk every bucket in order, aggregate, then fill gaps.
    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map_reduce(nil, fn bucket_start, last_value ->
      agg_value =
        case Map.fetch(grouped, bucket_start) do
          {:ok, points} -> aggregate(points, agg)
          :error -> nil
        end

      filled_value =
        case {agg_value, fill} do
          # carry forward (may still be nil)
          {nil, :forward} -> last_value
          {nil, nil} -> nil
          {v, _} -> v
        end

      next_last = if agg_value != nil, do: agg_value, else: last_value

      {{bucket_start, filled_value}, next_last}
    end)
    |> elem(0)
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

## Test harness — implement the `# TODO` test

```elixir
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

  test "fill: :forward starts with no carried value at the earliest bucket" do
    # The grid begins at the earliest point's floored bucket, so the leftmost
    # emitted bucket is never empty and never receives a carried value: it
    # holds its own aggregate under both fill modes, and the two modes differ
    # only in the interior gap.
    data = [{-3_000, 7}, {1_000, 9}]

    forward = TimeSeriesResampler.resample(data, @interval, agg: :sum, fill: :forward)
    nil_filled = TimeSeriesResampler.resample(data, @interval, agg: :sum, fill: nil)

    assert forward == [{-4_000, 7}, {-2_000, 7}, {0, 9}]
    assert nil_filled == [{-4_000, 7}, {-2_000, nil}, {0, 9}]
    assert hd(forward) == hd(nil_filled)
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

  test "first bucket floors a negative earliest timestamp downwards, not toward zero" do
    # floor(-100 / 2000) * 2000 = -1 * 2000 = -2000
    # floor( 100 / 2000) * 2000 =  0 * 2000 =     0
    data = [{-100, 1}, {100, 2}]
    result = TimeSeriesResampler.resample(data, 2_000, agg: :last, fill: nil)

    assert result == [{-2_000, 1}, {0, 2}]
  end

  test "negative timestamps are assigned to their floored bucket, not a truncated one" do
    # floor(-3000 / 2000) * 2000 = -2 * 2000 = -4000
    # floor(-1000 / 2000) * 2000 = -1 * 2000 = -2000
    data = [{-3_000, 1}, {-1_000, 2}]
    result = TimeSeriesResampler.resample(data, 2_000, agg: :count, fill: nil)

    assert result == [{-4_000, 1}, {-2_000, 1}]
  end

  test "omitting :agg defaults to :last" do
    # TODO
  end

  test "omitting :fill defaults to nil-filling empty buckets" do
    data = [{0, 10}, {4_100, 30}]
    result = TimeSeriesResampler.resample(data, 2_000, [])

    assert result == [{0, 10}, {2_000, nil}, {4_000, 30}]
  end

  test ":mean yields a float even when all bucket values are integers" do
    data = [{0, 10}, {1_500, 20}]
    [{0, mean}] = TimeSeriesResampler.resample(data, 2_000, agg: :mean, fill: nil)

    assert is_float(mean)
    assert mean == 15.0
  end
end
```
