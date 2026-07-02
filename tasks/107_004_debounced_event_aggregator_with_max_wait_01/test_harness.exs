defmodule DebounceAggregatorTest do
  use ExUnit.Case, async: false

  # Starts a DebounceAggregator under the test supervisor whose :on_flush
  # callback forwards each flushed batch back to the test process.
  defp start_agg(opts) do
    test_pid = self()

    defaults = [on_flush: fn batch -> send(test_pid, {:flushed, batch}) end]

    child_opts = Keyword.merge(defaults, opts)
    start_supervised!({DebounceAggregator, child_opts})
  end

  # ---------------------------------------------------------------
  # Idle (debounce) flush
  # ---------------------------------------------------------------

  test "flushes a coalesced batch after the stream goes idle" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    # Still within the idle window, nothing yet.
    refute_receive {:flushed, _}, 80

    # After the stream is quiet for idle_ms, both events flush as one batch.
    assert_receive {:flushed, [:a, :b]}, 500
  end

  test "each push resets the idle timer (debounce)" do
    agg = start_agg(idle_ms: 200, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)

    # Push :b before :a's idle window elapses; this resets the idle timer.
    Process.sleep(120)
    DebounceAggregator.push(agg, :b)

    # Idle is measured from :b now, so no flush should have happened yet
    # (a naive timer keyed to :a would have fired around here).
    refute_receive {:flushed, _}, 120

    # After quiet from :b, both events flush together — proving :a was NOT
    # flushed alone at its original idle deadline.
    assert_receive {:flushed, [:a, :b]}, 400
  end

  # ---------------------------------------------------------------
  # Max-wait cap
  # ---------------------------------------------------------------

  test "max_wait bounds latency even while pushes keep arriving" do
    agg = start_agg(idle_ms: 500, max_wait_ms: 300, batch_size: 1_000_000)

    # Push steadily at intervals shorter than idle_ms, so the idle timer keeps
    # resetting and can never fire — only max_wait can end the batch.
    DebounceAggregator.push(agg, :a)
    Process.sleep(120)
    DebounceAggregator.push(agg, :b)
    Process.sleep(120)
    DebounceAggregator.push(agg, :c)

    # max_wait started at :a (~t0) and fires ~t300 with everything buffered.
    assert_receive {:flushed, [:a, :b, :c]}, 400
  end

  # ---------------------------------------------------------------
  # Size flush
  # ---------------------------------------------------------------

  test "flushes immediately when the buffer reaches batch_size" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 3)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)

    assert_receive {:flushed, [:a, :b, :c]}, 500
  end

  # ---------------------------------------------------------------
  # No empty flushes / fresh batches
  # ---------------------------------------------------------------

  test "never flushes an empty batch" do
    start_agg(idle_ms: 100, max_wait_ms: 100, batch_size: 3)

    refute_receive {:flushed, _}, 400
  end

  test "starts a fresh batch after each flush" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 3)

    # A size flush first.
    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # A leftover single event must flush on the idle timer of a fresh batch.
    DebounceAggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    DebounceAggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end
end