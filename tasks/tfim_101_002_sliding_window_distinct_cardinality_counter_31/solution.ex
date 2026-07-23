  test "expired data is purged automatically on a 25ms cleanup interval" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: 25,
        max_window_ms: 1_000
      )

    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    # The key is now far outside the retention horizon. Nothing here sends the
    # process a :cleanup message, so tracked_key_count can only reach 0 if the
    # process wakes itself up on the configured interval.
    Clock.set(10_000)

    assert poll_until(fn -> SlidingUniqueCounter.tracked_key_count(sc) == 0 end, 1_000),
           "expired data was never purged by a self-scheduled cleanup"
  end