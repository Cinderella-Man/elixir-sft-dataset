defmodule KeyedAggregatorTest do
  use ExUnit.Case, async: false

  # Starts a KeyedAggregator under the test supervisor whose :on_flush callback
  # forwards each flushed key/batch back to the test process as
  # {:flushed, key, batch}.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn key, batch -> send(test_pid, {:flushed, key, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({KeyedAggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Size-triggered flush (per key)
  # ---------------------------------------------------------------

  test "flushes a key when it reaches the configured batch size" do
    agg = start_agg(batch_size: 3, interval_ms: 5_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)

    assert_receive {:flushed, :a, [1, 2, 3]}, 500
  end

  test "batch_size of 1 flushes every event for a key immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    KeyedAggregator.push(agg, :x, :first)
    assert_receive {:flushed, :x, [:first]}, 500

    KeyedAggregator.push(agg, :x, :second)
    assert_receive {:flushed, :x, [:second]}, 500
  end

  test "keys buffer and flush independently by size" do
    agg = start_agg(batch_size: 2, interval_ms: 5_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 10)
    KeyedAggregator.push(agg, :a, 2)

    # :a reached batch size and flushes; :b has one buffered event, no flush.
    assert_receive {:flushed, :a, [1, 2]}, 500
    refute_receive {:flushed, :b, _}, 150
  end

  # ---------------------------------------------------------------
  # Time-triggered flush (per key)
  # ---------------------------------------------------------------

  test "flushes each key's partial batch on its own interval" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 2)

    refute_receive {:flushed, _, _}, 80

    assert_receive {:flushed, :a, [1]}, 500
    assert_receive {:flushed, :b, [2]}, 500
  end

  test "does not flush empty keys on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    refute_receive {:flushed, _, _}, 400
  end

  test "keeps aggregating a key after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 500

    KeyedAggregator.push(agg, :a, 4)
    assert_receive {:flushed, :a, [4]}, 500

    KeyedAggregator.push(agg, :a, 5)
    assert_receive {:flushed, :a, [5]}, 500
  end

  # ---------------------------------------------------------------
  # Per-key timer reset
  # ---------------------------------------------------------------

  test "a key's interval timer resets after that key's size-triggered flush" do
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event under :a.
    KeyedAggregator.push(agg, :a, 1)

    # Complete the batch at t ~= 200 to force a size-triggered flush.
    Process.sleep(200)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 300

    # New event for :a right after the flush (t ~= 200).
    KeyedAggregator.push(agg, :a, 4)

    # A stale timer from the start would fire at t ~= 400 and flush [4]. With a
    # correct reset, that does NOT happen within the next ~300ms.
    refute_receive {:flushed, :a, _}, 300

    # The reset timer flushes [4] ~400ms after the flush at t ~= 200.
    assert_receive {:flushed, :a, [4]}, 400
  end

  test "flushing one key does not reset another key's timer" do
    agg = start_agg(batch_size: 2, interval_ms: 250)

    # :b starts its interval timer at t ~= 0.
    KeyedAggregator.push(agg, :b, 100)

    # Halfway through :b's interval, force a size flush of :a.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    assert_receive {:flushed, :a, [1, 2]}, 300

    # :b must still flush on its ORIGINAL schedule (~250ms from t=0), not be
    # reset by :a's flush.
    assert_receive {:flushed, :b, [100]}, 300
  end
end