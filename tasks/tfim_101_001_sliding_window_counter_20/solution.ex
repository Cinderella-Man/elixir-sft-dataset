  test "cleanup keeps the bucket sitting exactly on the retention boundary", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        max_window_ms: 500,
        cleanup_interval_ms: :infinity
      )

    SlidingCounter.increment(pid, "edge")

    # At now = 500 the bucket starting at 0 sits exactly on the horizon. A count
    # over the full 500 ms window still sees it, and cleanup must never delete
    # data a legal count could still return — so it must survive the pass.
    Clock.set(500)
    send(pid, :cleanup)
    assert 1 = SlidingCounter.count(pid, "edge", 500)
  end