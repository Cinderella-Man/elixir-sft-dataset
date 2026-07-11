  test "different keys are completely independent", %{sc: sc} do
    for _ <- 1..3, do: SlidingCounter.increment(sc, "a")
    for _ <- 1..7, do: SlidingCounter.increment(sc, "b")

    assert 3 = SlidingCounter.count(sc, "a", 1_000)
    assert 7 = SlidingCounter.count(sc, "b", 1_000)
  end