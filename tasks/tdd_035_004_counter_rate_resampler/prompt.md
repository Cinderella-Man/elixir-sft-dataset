# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], 1_000, fill: :empty)
    end
  end

  test "a non-integer or negative interval raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], 1_000.0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], -1_000, mode: :delta)
    end
  end

  test "an omitted :mode defaults to :delta while other options are explicit" do
    # Increments +50 and +50 both land in bucket 0.  Under :delta the bucket is
    # the integer 50 + 50 = 100; under :rate it would be the float 100.0, so the
    # strict comparison discriminates the two modes.
    data = [{0, 100}, {300, 150}, {700, 200}]
    result = CounterResampler.resample(data, @interval, reset: :detect, fill: :zero)

    assert result === [{0, 100}]
  end

  test "an omitted :reset defaults to :detect while other options are explicit" do
    # The pair 100 -> 40 decreases, so reset detection attributes the later
    # value 40 to bucket 0; :raw would have attributed -60 instead.
    data = [{0, 100}, {300, 40}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)

    assert result == [{0, 40}]
  end

  test "an omitted :fill defaults to :zero while other options are explicit" do
    # Bucket 1000 receives no increment; the default fill makes it 0, not nil.
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, reset: :detect)

    assert result === [{0, 50}, {1_000, 0}, {2_000, 250}]
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
