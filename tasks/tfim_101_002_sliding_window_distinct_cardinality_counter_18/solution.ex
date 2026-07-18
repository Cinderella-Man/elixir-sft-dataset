  test "window_ms smaller than bucket_ms still works", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")
    # A 50ms window with 100ms buckets — member is still in the current bucket
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 50)

    Clock.advance(150)
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 50)
  end