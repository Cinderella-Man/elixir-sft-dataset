  test "max_window_ms defaults to 3_600_000 as the cleanup retention horizon" do
    {:ok, sc} =
      SlidingUniqueCounter.start_link(
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity
      )

    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # The member's bucket starts at 0; at now=3_600_000 the retention threshold
    # is also 0, so the key is still within the horizon.
    Clock.set(3_600_000)
    send(sc, :cleanup)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    # One bucket later the threshold has moved past the bucket start.
    Clock.set(3_600_101)
    send(sc, :cleanup)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end