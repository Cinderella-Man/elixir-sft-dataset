  test "expired keys are removed during cleanup", %{sc: sc} do
    for i <- 1..50 do
      SlidingCounter.increment(sc, "key:#{i}")
    end

    # Let all windows expire — well past the default horizon of bucket_ms * 60.
    Clock.advance(10_000)

    send(sc, :cleanup)

    # A window far wider than the retention horizon would still report these
    # events if their buckets were merely stale rather than dropped. Every key
    # reads 0, so cleanup evicted the data itself. The first synchronous count
    # also guarantees the :cleanup message has already been processed.
    for i <- 1..50 do
      assert 0 = SlidingCounter.count(sc, "key:#{i}", 100_000)
    end
  end