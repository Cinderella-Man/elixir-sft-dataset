  test "default bucket_ms is 1000: an event at t=999 belongs to the bucket at 0", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(999)
    SlidingCounter.increment(pid, "k")
    Clock.set(1_999)

    # Bucket 0 (starting at time 0) now lies entirely outside a 1000 ms window.
    assert 0 = SlidingCounter.count(pid, "k", 1_000)
  end