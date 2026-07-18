# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CounterResampler do
  @moduledoc """
  Resamples readings from a monotonically increasing counter into fixed-interval
  buckets of per-interval increase (`:delta`) or per-second rate (`:rate`), with
  optional counter-reset detection.

  Because the samples are cumulative, values are derived from the *change*
  between consecutive samples. Each consecutive increment is attributed to the
  bucket of the later sample, and a bucket's value is the sum of the increments
  attributed to it.
  """

  @type datapoint :: {integer(), number()}
  @type mode :: :delta | :rate
  @type reset :: :detect | :raw
  @type fill :: :zero | nil

  @valid_mode [:delta, :rate]
  @valid_reset [:detect, :raw]
  @valid_fill [:zero, nil]

  @doc """
  Resamples cumulative counter `data` into fixed `interval_ms` buckets.

  `data` is a list of `{timestamp_ms, counter_value}` tuples at irregular
  intervals (unordered input is sorted internally). `interval_ms` is the bucket
  width in milliseconds and must be a positive integer.

  Supported `opts`:

    * `:mode` — `:delta` (default) emits the counter increase attributed to each
      bucket; `:rate` divides that increase by `interval_ms / 1000` seconds.
    * `:reset` — `:detect` (default) treats a decrease between two consecutive
      samples as a counter reset (using the later value as the increment); `:raw`
      keeps the raw difference (which may be negative).
    * `:fill` — `:zero` (default) or `:nil`, choosing how buckets with no measured
      increase are filled.

  Timestamps may be negative; they are floored toward negative infinity onto the
  `interval_ms` grid.

  Arguments are always validated, even for an empty `data` list: a non-positive or
  non-integer `interval_ms`, or an option value outside the documented sets, raises
  an `ArgumentError`.

  Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending
  by bucket start. Empty input returns `[]`.
  """
  @spec resample([datapoint()], pos_integer(), keyword()) :: [{integer(), number() | nil}]
  def resample(data, interval_ms, opts \\ [])

  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    mode = fetch_opt!(opts, :mode, :delta, @valid_mode)
    reset = fetch_opt!(opts, :reset, :detect, @valid_reset)
    fill = fetch_opt!(opts, :fill, :zero, @valid_fill)

    do_resample(data, interval_ms, mode, reset, fill)
  end

  def resample(_data, interval_ms, _opts) do
    raise ArgumentError,
          "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp do_resample([], _interval_ms, _mode, _reset, _fill), do: []

  defp do_resample(data, interval_ms, mode, reset, fill) do
    sorted = Enum.sort_by(data, &elem(&1, 0))

    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    increments =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(%{}, fn [{_t0, v0}, {t1, v1}], acc ->
        inc = increment(v0, v1, reset)
        bucket = floor_bucket(t1, interval_ms)
        Map.update(acc, bucket, inc, &(&1 + inc))
      end)

    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map(fn bucket_start ->
      value =
        case Map.fetch(increments, bucket_start) do
          {:ok, inc} -> project(inc, mode, interval_ms)
          :error -> empty_value(mode, interval_ms, fill)
        end

      {bucket_start, value}
    end)
  end

  defp increment(v0, v1, :raw), do: v1 - v0

  defp increment(v0, v1, :detect) do
    if v1 < v0, do: v1, else: v1 - v0
  end

  defp project(inc, :delta, _interval_ms), do: inc
  defp project(inc, :rate, interval_ms), do: inc / (interval_ms / 1000)

  defp empty_value(_mode, _interval_ms, nil), do: nil
  defp empty_value(mode, interval_ms, :zero), do: project(0, mode, interval_ms)

  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms

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
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: nil)

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

    nil_result = CounterResampler.resample([{300, 100}], @interval, mode: :delta, fill: nil)
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

  test "with no options the defaults are :delta, :detect and :zero" do
    # Samples exercising all three defaults at once:
    #   t=0    v=100   first sample, no predecessor
    #   t=300  v=150   (+50, bucket 0)
    #   t=1000..1999   no sample -> empty bucket, must fill (not nil)
    #   t=2300 v=400   (+250, bucket 2000)
    #   t=2800 v=50    decrease -> reset detection gives +50 (raw would give -350)
    data = [{0, 100}, {300, 150}, {2_300, 400}, {2_800, 50}]
    result = CounterResampler.resample(data, @interval, [])

    # Strict comparison: :rate would emit floats, :raw would make bucket 2000
    # -100, and fill: nil would make bucket 1000 nil.
    assert result === [{0, 50}, {1_000, 0}, {2_000, 300}]
  end

  test "argument validation happens even when the data list is empty" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 1_000, mode: :average)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 1_000, reset: :ignore)
    end
  end

  test "negative timestamps floor down to their bucket boundary" do
    # floor(-1500/1000) = -2 -> -2000, floor(-300/1000) = -1 -> -1000,
    # floor(200/1000) = 0 -> 0.  Increment +30 lands in bucket -1000 (later
    # sample t=-300), increment +50 lands in bucket 0 (later sample t=200).
    data = [{-1_500, 10}, {-300, 40}, {200, 90}]
    result = CounterResampler.resample(data, 1_000, mode: :delta, fill: :zero)

    assert result == [{-2_000, 0}, {-1_000, 30}, {0, 50}]
  end

  test "empty buckets fill with nil in :rate mode when requested" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, 1_000, mode: :rate, fill: nil)

    assert [{0, r0}, {1_000, gap}, {2_000, r2}] = result
    assert gap == nil
    assert_in_delta r0, 50.0, 0.0001
    assert_in_delta r2, 250.0, 0.0001
  end

  test ":rate scales by a sub-second interval length" do
    # interval 500ms = 0.5s, so an increment of +50 becomes 100.0 per second.
    data = [{0, 100}, {200, 150}, {700, 200}]
    result = CounterResampler.resample(data, 500, mode: :rate, fill: :zero)

    assert [{0, r0}, {500, r1}] = result
    assert_in_delta r0, 100.0, 0.0001
    assert_in_delta r1, 100.0, 0.0001
  end

  test "an undocumented :fill value raises ArgumentError" do
    # TODO
  end

  test "a non-integer or negative interval raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], 1_000.0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], -1_000, mode: :delta)
    end
  end
end
```
