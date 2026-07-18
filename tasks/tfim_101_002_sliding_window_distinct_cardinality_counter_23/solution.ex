  test "bucket_ms defaults to 1_000" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    Clock.set(900)
    SlidingUniqueCounter.add(sc, "k", "early")

    # With 1_000ms buckets, "early" sits in bucket 0, which starts at 0. At
    # now=1_000 a 500ms window keeps only buckets starting at or after 500.
    Clock.set(1_000)
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 500)

    # "late" lands in bucket 1, which starts exactly at 1_000 and so is inside
    # a 1ms window at now=1_000 (threshold 999).
    SlidingUniqueCounter.add(sc, "k", "late")
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1)
  end