  test "a key's next time flush is one interval after its next push, not after the flush" do
    agg = start_agg(batch_size: 5, interval_ms: 300)

    # t ~= 0 push, time-triggered flush at t ~= 300.
    KeyedAggregator.push(agg, :a, 1)
    assert_receive {:flushed, :a, [1]}, 1_000
    flushed_at = System.monotonic_time(:millisecond)

    # Next push for :a happens ~150ms after the flush. Its deadline must be one
    # full interval after THAT push, not 300ms after the flush.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 2)

    # A timer anchored to the previous flush would fire ~300ms after `flushed_at`,
    # i.e. ~150ms from now. Nothing may arrive in that window.
    refute_receive {:flushed, :a, _}, 200
    assert System.monotonic_time(:millisecond) - flushed_at >= 300

    assert_receive {:flushed, :a, [2]}, 500
  end