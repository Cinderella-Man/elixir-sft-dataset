  test "bucket starting exactly at now minus window_ms is included, one ms later excluded", %{
    sc: sc
  } do
    SlidingCounter.increment(sc, "edge")

    # Bucket 0 starts at 0; at now = 500 with a 500 ms window, window_start = 0,
    # so the bucket start is exactly on the inclusive old edge.
    Clock.set(500)
    assert 1 = SlidingCounter.count(sc, "edge", 500)

    # One millisecond later window_start = 1 > 0, so the bucket contributes nothing
    # at all even though its range overlaps the leading edge.
    Clock.set(501)
    assert 0 = SlidingCounter.count(sc, "edge", 500)
  end