  test "default retention is exactly 60 buckets of history", %{sc: sc} do
    SlidingCounter.increment(sc, "old")

    # 59.5 bucket-widths later, the event's bucket is still inside bucket_ms * 60.
    Clock.set(5_950)
    send(sc, :cleanup)
    assert 1 = SlidingCounter.count(sc, "old", 100_000)

    # 60.5 bucket-widths later it has aged past the default horizon; cleanup drops it.
    Clock.set(6_050)
    send(sc, :cleanup)
    assert 0 = SlidingCounter.count(sc, "old", 100_000)
  end