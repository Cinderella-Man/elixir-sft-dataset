  test "multiple increments are all counted within the window", %{sc: sc} do
    for _ <- 1..5, do: SlidingCounter.increment(sc, "k")
    assert 5 = SlidingCounter.count(sc, "k", 1_000)
  end