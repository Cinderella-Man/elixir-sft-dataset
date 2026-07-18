  test "very large window includes all increments", %{sc: sc} do
    for i <- 0..4 do
      Clock.set(i * 10_000)
      SlidingCounter.increment(sc, "k")
    end

    Clock.set(40_000)
    assert 5 = SlidingCounter.count(sc, "k", 86_400_000)
  end