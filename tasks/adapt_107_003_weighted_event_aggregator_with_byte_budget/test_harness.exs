defmodule WeightedAggregatorTest do
  use ExUnit.Case, async: false

  # Starts a WeightedAggregator under the test supervisor whose :on_flush
  # callback forwards each flushed batch back to the test process.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn batch -> send(test_pid, {:flushed, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({WeightedAggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Weight-triggered flush
  # ---------------------------------------------------------------

  test "flushes when accumulated weight reaches the byte budget" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 4)
    WeightedAggregator.push(agg, 4)

    # Total weight 8 < 10, so nothing yet.
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(agg, 3)
    # Total weight 11 >= 10 -> flush the whole buffer in push order.
    assert_receive {:flushed, [4, 4, 3]}, 500
  end

  test "a single oversized event flushes immediately" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 50)
    assert_receive {:flushed, [50]}, 500
  end

  test "the default size_fn measures binary byte size" do
    agg = start_agg(max_bytes: 5, interval_ms: 5_000)

    WeightedAggregator.push(agg, "abc")
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(agg, "de")
    # 3 + 2 = 5 >= 5 -> flush.
    assert_receive {:flushed, ["abc", "de"]}, 500
  end

  test "accumulated weight resets to zero after a flush" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 6)
    WeightedAggregator.push(agg, 6)
    assert_receive {:flushed, [6, 6]}, 500

    WeightedAggregator.push(agg, 3)
    refute_receive {:flushed, _}, 100

    WeightedAggregator.push(agg, 8)
    assert_receive {:flushed, [3, 8]}, 500
  end

  # ---------------------------------------------------------------
  # Time-triggered flush
  # ---------------------------------------------------------------

  test "flushes a below-budget partial batch after the interval" do
    agg = start_agg(max_bytes: 100, interval_ms: 200, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 5)
    WeightedAggregator.push(agg, 3)

    refute_receive {:flushed, _}, 80
    assert_receive {:flushed, [5, 3]}, 500
  end

  test "does not flush empty batches on the interval" do
    start_agg(max_bytes: 10, interval_ms: 150, size_fn: fn n -> n end)

    refute_receive {:flushed, _}, 400
  end

  # ---------------------------------------------------------------
  # Timer reset after each flush
  # ---------------------------------------------------------------

  test "the interval timer resets after a weight-triggered flush" do
    agg = start_agg(max_bytes: 100, interval_ms: 400, size_fn: fn n -> n end)

    # t ~= 0: buffer weight 10.
    WeightedAggregator.push(agg, 10)

    # At t ~= 200, push a heavy event to force a weight-triggered flush.
    Process.sleep(200)
    WeightedAggregator.push(agg, 95)
    assert_receive {:flushed, [10, 95]}, 300

    # New event right after the flush (t ~= 200).
    WeightedAggregator.push(agg, 5)

    # A stale timer from start would fire at t ~= 400 and flush [5]. With a
    # correct reset it does NOT happen within the next ~300ms.
    refute_receive {:flushed, _}, 300

    # The reset timer flushes [5] ~400ms after the flush at t ~= 200.
    assert_receive {:flushed, [5]}, 400
  end

  # ---------------------------------------------------------------
  # Budget boundary and weight bookkeeping
  # ---------------------------------------------------------------

  test "one under the budget stays buffered; exactly the budget flushes" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Total weight 9 = max_bytes - 1: strictly below the budget, no flush.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    # 9 + 1 = 10 >= 10 -> flush exactly at the budget.
    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end

  test "the accumulated weight restarts from exactly zero after a flush" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Oversized event -> immediate flush; buffer and weight reset.
    WeightedAggregator.push(agg, 10)
    assert_receive {:flushed, [10]}, 500

    # After the reset, 9 = max_bytes - 1 must sit strictly below the budget.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end

  test "the default on_flush is a no-op the aggregator can call safely" do
    agg = start_supervised!({WeightedAggregator, [max_bytes: 5, interval_ms: 5_000]})
    ref = Process.monitor(agg)

    # 11 bytes >= 5 -> a weight-triggered flush through the default callback.
    WeightedAggregator.push(agg, "hello world")

    # The default callback must not take the aggregator down: it survives the
    # flush and keeps accepting further pushes.
    refute_receive {:DOWN, ^ref, :process, ^agg, _}, 200

    WeightedAggregator.push(agg, "another oversized event")
    refute_receive {:DOWN, ^ref, :process, ^agg, _}, 200

    assert Process.alive?(agg)
  end

  test "a time-triggered flush leaves an empty buffer and zero accumulated weight" do
    agg = start_agg(max_bytes: 10, interval_ms: 200, size_fn: fn n -> n end)

    # 9 < 10 stays buffered until the interval elapses.
    WeightedAggregator.push(agg, 9)
    assert_receive {:flushed, [9]}, 500

    # If the weight survived the time flush, 9 + 9 = 18 >= 10 would flush at once.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    # A fresh buffer starting from zero: 9 + 1 = 10 >= 10 flushes exactly here.
    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end

  test "the default byte budget is 1_048_576" do
    agg = start_agg(interval_ms: 5_000)

    big = :binary.copy("a", 1_048_575)

    # One byte under the default budget: strictly below, so no flush.
    WeightedAggregator.push(agg, big)
    refute_receive {:flushed, _}, 100

    # 1_048_575 + 1 = 1_048_576 >= the default budget -> flush.
    WeightedAggregator.push(agg, "b")
    assert_receive {:flushed, [^big, "b"]}, 500
  end

  test "events can be pushed through a registered name" do
    start_agg(
      name: :weighted_aggregator_named_target,
      max_bytes: 10,
      interval_ms: 5_000,
      size_fn: fn n -> n end
    )

    WeightedAggregator.push(:weighted_aggregator_named_target, 4)
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(:weighted_aggregator_named_target, 6)
    assert_receive {:flushed, [4, 6]}, 500
  end

  test "push returns :ok for both a buffering and a flushing event" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Buffering-only push.
    assert :ok = WeightedAggregator.push(agg, 3)
    refute_receive {:flushed, _}, 80

    # Push that triggers a flush must also just return :ok.
    assert :ok = WeightedAggregator.push(agg, 7)
    assert_receive {:flushed, [3, 7]}, 500
  end
end
