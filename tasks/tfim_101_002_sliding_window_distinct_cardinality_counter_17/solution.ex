  test "distinct members are pruned as the window slides", %{sc: sc} do
    # Spread distinct members across many buckets
    for i <- 0..9 do
      Clock.set(i * 200)
      SlidingUniqueCounter.add(sc, "k", "u#{i}")
    end

    # At t=2000, a 1000ms window covers buckets whose start >= 1000 (u5..u9)
    Clock.set(2_000)
    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end