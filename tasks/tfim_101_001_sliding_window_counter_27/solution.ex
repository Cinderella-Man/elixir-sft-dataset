  test "cleanup runs on its own timer and keeps re-arming for later rounds", %{sc: _sc} do
    interval = 25
    # Generously wider than the interval so a slow scheduler is not mistaken
    # for a missing one; only a server that never fires can exhaust it.
    deadline_ms = 20 * interval

    Clock.set(0)

    {:ok, pid} =
      SlidingCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        max_window_ms: 500,
        cleanup_interval_ms: interval
      )

    SlidingCounter.increment(pid, "auto")

    # Still live: a wide window sees the event until cleanup physically drops it.
    assert 1 = SlidingCounter.count(pid, "auto", 100_000)

    # Push the clock far past the retention horizon and wait for the timer, which
    # nobody triggered by hand, to evict the aged bucket.
    Clock.set(10_000)

    assert poll_until(fn -> SlidingCounter.count(pid, "auto", 100_000) == 0 end, deadline_ms),
           "the periodic timer never fired a first automatic cleanup"

    # Second round: a fresh event that ages out afterwards can only be dropped by
    # a timer that was re-armed after the first cleanup was handled.
    Clock.set(20_000)
    SlidingCounter.increment(pid, "auto2")
    assert 1 = SlidingCounter.count(pid, "auto2", 100_000)

    Clock.set(40_000)

    assert poll_until(fn -> SlidingCounter.count(pid, "auto2", 100_000) == 0 end, deadline_ms),
           "the periodic timer did not re-arm after handling a cleanup"
  end