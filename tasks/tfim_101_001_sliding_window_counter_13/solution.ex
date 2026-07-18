  test "sub-buckets for a key are pruned as the window slides", %{sc: sc} do
    # Spread increments across many buckets
    for i <- 0..9 do
      Clock.set(i * 200)
      SlidingCounter.increment(sc, "k")
    end

    # At t=2000, window of 1000ms covers buckets from t=1000 onward (5 events)
    Clock.set(2_000)
    assert 5 = SlidingCounter.count(sc, "k", 1_000)
  end