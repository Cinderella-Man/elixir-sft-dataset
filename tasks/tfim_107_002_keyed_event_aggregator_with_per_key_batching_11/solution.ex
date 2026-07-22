  test "defaults :interval_ms to exactly 1_000 ms for a key's time-triggered flush" do
    # No :interval_ms given, so the documented default of 1_000 ms applies; the
    # batch size is large enough that only the time trigger can fire.
    agg = start_agg(batch_size: 50)

    before_push = System.monotonic_time(:microsecond)
    KeyedAggregator.push(agg, :a, :only)
    assert_receive {:flushed, :a, [:only]}, 5_000
    elapsed_us = System.monotonic_time(:microsecond) - before_push

    # The key's timer is armed at (or after) the push, so a correct 1_000 ms
    # interval can never deliver the flush sooner than 1_000 ms after the push.
    # The upper bound leaves room for scheduler jitter while still ruling out
    # any other plausible default (500 ms, 2_000 ms, ...).
    assert elapsed_us >= 1_000_000
    assert elapsed_us < 1_500_000
  end