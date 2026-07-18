  test "default bucket_ms is 1000: an amount at t=1000 starts a new bucket", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(1_000)
    SlidingSum.add(sc2, "k", 5)

    # Bucket 1 starts exactly at 1000; the cutoff quantizes to bucket starts
    # and the old side is inclusive, so even a 1 ms window still sees it.
    assert 5 == SlidingSum.sum(sc2, "k", 1)
  end