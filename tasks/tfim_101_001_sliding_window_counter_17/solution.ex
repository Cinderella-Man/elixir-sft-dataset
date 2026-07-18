  test "default bucket_ms is 1000: an event at t=1000 starts a new bucket", %{sc: _sc} do
    {:ok, pid} =
      SlidingCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(1_000)
    SlidingCounter.increment(pid, "k")

    # Bucket 1 starts exactly at 1000, so even a 1 ms window still sees it:
    # the cutoff quantizes to bucket starts and the old side is inclusive.
    assert 1 = SlidingCounter.count(pid, "k", 1)
  end