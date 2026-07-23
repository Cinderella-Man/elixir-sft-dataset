# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
defmodule AggregatorTest do
  use ExUnit.Case, async: false

  # Starts an Aggregator under the test supervisor whose :on_flush callback
  # forwards each flushed batch back to the test process as {:flushed, batch}.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn batch -> send(test_pid, {:flushed, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({Aggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Size-triggered flush
  # ---------------------------------------------------------------

  test "flushes immediately when the batch reaches the configured size" do
    # Long interval so only the size trigger can fire.
    agg = start_agg(batch_size: 3, interval_ms: 5_000)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)

    assert_receive {:flushed, [:a, :b, :c]}, 500
  end

  test "batch_size of 1 flushes every event immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    Aggregator.push(agg, :x)
    assert_receive {:flushed, [:x]}, 500

    Aggregator.push(agg, :y)
    assert_receive {:flushed, [:y]}, 500
  end

  test "multiple full batches flush in order with fresh buffers" do
    agg = start_agg(batch_size: 2, interval_ms: 5_000)

    Aggregator.push(agg, 1)
    Aggregator.push(agg, 2)
    Aggregator.push(agg, 3)
    Aggregator.push(agg, 4)

    assert_receive {:flushed, [1, 2]}, 500
    assert_receive {:flushed, [3, 4]}, 500
  end

  # ---------------------------------------------------------------
  # Time-triggered flush
  # ---------------------------------------------------------------

  test "flushes buffered events after the interval when below batch size" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)

    # Below batch size, so nothing should flush right away.
    refute_receive {:flushed, _}, 80

    # Eventually the interval elapses and the partial batch is flushed.
    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "does not flush empty batches on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    # No pushes at all — the callback must never be invoked, even across
    # multiple interval periods.
    refute_receive {:flushed, _}, 400
  end

  test "keeps aggregating after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    # First a size flush.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # Then a leftover single event that must flush on the timer.
    Aggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    Aggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end

  # ---------------------------------------------------------------
  # Timer reset after each flush
  # ---------------------------------------------------------------

  test "the interval timer resets after a size-triggered flush" do
    # interval 400ms, batch size 3.
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event.
    Aggregator.push(agg, :a)

    # Wait ~200ms (half the interval), then complete the batch to force a
    # size-triggered flush at t ~= 200ms.
    Process.sleep(200)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 300

    # Immediately push a new event (t ~= 200ms).
    Aggregator.push(agg, :d)

    # If the timer had NOT been reset, a stale timer from start would fire at
    # t ~= 400ms and flush [:d]. Assert that does NOT happen within the next
    # ~300ms (up to t ~= 500ms).
    refute_receive {:flushed, _}, 300

    # With a correct reset, the flush for [:d] happens ~400ms after the flush
    # at t ~= 200ms, i.e. around t ~= 600ms.
    assert_receive {:flushed, [:d]}, 400
  end

  # ---------------------------------------------------------------
  # Option defaults
  # ---------------------------------------------------------------

  test "batch_size defaults to 100 when not provided" do
    # Long interval so only the size trigger can fire; :batch_size omitted.
    agg = start_agg(interval_ms: 5_000)

    Enum.each(1..99, fn n -> Aggregator.push(agg, n) end)

    # 99 buffered events is still one short of the documented default of 100.
    refute_receive {:flushed, _}, 200

    Aggregator.push(agg, 100)

    assert_receive {:flushed, batch}, 500
    assert batch == Enum.to_list(1..100)
  end

  test "interval_ms defaults to 1_000 when not provided" do
    # Batch size large enough that only the time trigger can fire.
    agg = start_agg(batch_size: 50)

    Aggregator.push(agg, :a)

    # A default of 1_000ms means no flush is due yet at ~700ms.
    refute_receive {:flushed, _}, 700

    # But the partial batch must be flushed once the default interval elapses.
    assert_receive {:flushed, [:a]}, 800
  end

  test "on_flush defaults to a no-op so the aggregator survives flushes without it" do
    # No :on_flush given at all: flushing must not crash the process.
    agg = start_supervised!({Aggregator, [batch_size: 2, interval_ms: 100]})
    ref = Process.monitor(agg)

    # Force a size-triggered flush, then a time-triggered flush of a leftover.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)

    refute_receive {:DOWN, ^ref, :process, ^agg, _reason}, 500
    assert Process.alive?(agg)
  end

  # ---------------------------------------------------------------
  # Name registration
  # ---------------------------------------------------------------

  test "registers under :name and accepts pushes addressed to that name" do
    name = :"aggregator_#{System.pid()}_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 2, interval_ms: 5_000)

    assert Process.whereis(name) == pid

    # push/2 must accept the registered name, not just a pid.
    Aggregator.push(name, :a)
    Aggregator.push(name, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "time-based flush is due a full interval after the flush, even if the event is pushed late" do
    # Interval 400ms, batch size 2 so we can force a size flush at t ~= 0.
    agg = start_agg(batch_size: 2, interval_ms: 400)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    assert_receive {:flushed, [:a, :b]}, 500

    # The most recent flush happened at t ~= 0, so the next time-based flush is
    # due at t ~= 400 — regardless of when the event that fills the buffer
    # arrives. Push :c at t ~= 250, i.e. only ~150ms before that deadline.
    Process.sleep(250)
    Aggregator.push(agg, :c)

    # Anchored on the flush (as promised), [:c] flushes ~150ms from now.
    # Anchored on the push instead, it would take a further ~400ms.
    assert_receive {:flushed, [:c]}, 280
  end

  test "time-based flush is due a full interval after start when the first event arrives late" do
    # Batch size high enough that only the time trigger can fire.
    agg = start_agg(batch_size: 5, interval_ms: 400)

    # No flush has happened yet, so the interval is measured from start:
    # the deadline is t ~= 400. Buffer an event at t ~= 250.
    Process.sleep(250)
    Aggregator.push(agg, :a)

    # Measured from start (as promised), [:a] flushes ~150ms from now.
    # Measured from the push instead, it would take a further ~400ms.
    assert_receive {:flushed, [:a]}, 280
  end

  test "push returns :ok for both a pid and a registered name" do
    name = :"aggregator_push_ret_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 5, interval_ms: 5_000)

    assert Aggregator.push(pid, :a) == :ok
    assert Aggregator.push(name, :b) == :ok
  end

  # ---------------------------------------------------------------
  # The interval fires on its own
  # ---------------------------------------------------------------

  test "the aggregator flushes on its own schedule with no external trigger" do
    # 25ms interval, batch size far out of reach: the only thing that can ever
    # deliver this event is the aggregator's own elapsed-interval flush.
    agg = start_agg(batch_size: 1_000, interval_ms: 25)

    Aggregator.push(agg, :tick)

    assert_receive {:flushed, [:tick]}, 2_000
  end

  test "a second interval flush follows the first without any further prompting" do
    agg = start_agg(batch_size: 1_000, interval_ms: 25)

    Aggregator.push(agg, :first)
    assert_receive {:flushed, [:first]}, 2_000

    # The timer keeps running after a flush, so a later event is picked up by
    # the next automatic firing too.
    Aggregator.push(agg, :second)
    assert_receive {:flushed, [:second]}, 2_000
  end

  # ---------------------------------------------------------------
  # Starting with no options
  # ---------------------------------------------------------------

  test "starts with an empty option list and keeps accepting pushes" do
    # Every option is optional, so a bare start must succeed and stay healthy.
    agg = start_supervised!({Aggregator, []})
    ref = Process.monitor(agg)

    assert Aggregator.push(agg, :a) == :ok
    assert Aggregator.push(agg, :b) == :ok

    refute_receive {:DOWN, ^ref, :process, ^agg, _reason}, 300
    assert Process.alive?(agg)
  end

  test "a :name registration is honoured for non-atom names passed to GenServer" do
    gname = {:global, :"aggregator_global_#{System.pid()}_#{System.unique_integer([:positive])}"}

    start_agg(name: gname, batch_size: 2, interval_ms: 5_000)

    # :name is handed straight to GenServer.start_link/3, so any server name it
    # accepts must work for registration and for push/2.
    assert Aggregator.push(gname, :a) == :ok
    Aggregator.push(gname, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end
end
```

Send back the implementation only — one file, no tests.
