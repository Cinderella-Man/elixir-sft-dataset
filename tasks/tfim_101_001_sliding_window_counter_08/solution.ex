  test "count drops to zero once all events expire", %{sc: sc} do
    for _ <- 1..4, do: SlidingCounter.increment(sc, "k")

    Clock.advance(2_000)

    assert 0 = SlidingCounter.count(sc, "k", 1_000)
  end