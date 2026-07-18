  test "default bucket_ms is 1000: an amount at t=999 belongs to the bucket at 0", %{sc: _sc} do
    {:ok, sc2} = SlidingSum.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(999)
    SlidingSum.add(sc2, "k", 5)
    Clock.set(1_999)

    # Bucket 0 (starting at time 0) lies entirely outside a 1000 ms window now.
    assert 0 == SlidingSum.sum(sc2, "k", 1_000)
  end