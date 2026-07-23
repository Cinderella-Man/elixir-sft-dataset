  test "cleanup fires automatically on the configured interval" do
    start_supervised!(TickClock)

    start_supervised!(
      {SlidingAlerter,
       [
         clock: &TickClock.now/0,
         bucket_ms: 100,
         threshold: 3,
         window_ms: 1_000,
         cleanup_interval_ms: 25
       ]}
    )

    # No public call is made against this server, so the only reader of the
    # injected clock is the periodic cleanup. Observing two clock reads shows
    # cleanup fired and re-scheduled itself on its own, well inside a deadline
    # many times the 25ms interval. The test never sends :cleanup itself.
    deadline = System.monotonic_time(:millisecond) + 2_000
    assert wait_for_ticks(2, deadline)
  end