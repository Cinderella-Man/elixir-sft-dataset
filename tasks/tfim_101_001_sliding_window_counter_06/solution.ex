  test "events exactly at the window boundary are counted", %{sc: sc} do
    SlidingCounter.increment(sc, "k")

    # Advance to just inside the window
    Clock.advance(999)

    assert 1 = SlidingCounter.count(sc, "k", 1_000)
  end