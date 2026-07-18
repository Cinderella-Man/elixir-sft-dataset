  test "window_ms smaller than bucket_ms still works", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    # A 50ms window with 100ms buckets — event is still in the current bucket
    assert 1 = SlidingCounter.count(sc, "k", 50)

    Clock.advance(150)
    assert 0 = SlidingCounter.count(sc, "k", 50)
  end