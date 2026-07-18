  test "very large window includes all distinct members", %{sc: sc} do
    for i <- 0..4 do
      Clock.set(i * 10_000)
      SlidingUniqueCounter.add(sc, "k", "u#{i}")
    end

    Clock.set(40_000)
    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 86_400_000)
  end