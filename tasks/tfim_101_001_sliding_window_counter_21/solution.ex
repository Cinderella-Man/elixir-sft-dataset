  test "negative clock times bucket by floor division and slide correctly", %{sc: sc} do
    Clock.set(-250)
    SlidingCounter.increment(sc, "neg")

    # now = -250, window 100 => window_start = -350; the bucket [-300, -200) starts
    # at -300 >= -350, so it counts.
    assert 1 = SlidingCounter.count(sc, "neg", 100)

    # Crossing zero: an event at -50 sits in bucket [-100, 0) and is still visible
    # from now = 0 with a 100 ms window (bucket start -100 >= -100).
    Clock.set(-50)
    SlidingCounter.increment(sc, "cross")
    Clock.set(0)
    assert 1 = SlidingCounter.count(sc, "cross", 100)

    # The old -250 event's bucket starts at -300, well before 0 - 100, so it is gone.
    assert 0 = SlidingCounter.count(sc, "neg", 100)
  end