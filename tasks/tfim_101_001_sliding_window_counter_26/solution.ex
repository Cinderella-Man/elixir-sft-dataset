  test "repeated counts with an unchanged clock are stable and non-destructive", %{sc: sc} do
    for _ <- 1..3, do: SlidingCounter.increment(sc, "k")

    # Counting an unknown key must not create an entry or disturb anything.
    assert 0 = SlidingCounter.count(sc, "ghost", 1_000)
    assert 0 = SlidingCounter.count(sc, "ghost", 1_000)

    assert 3 = SlidingCounter.count(sc, "k", 1_000)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)

    # Reads left the data intact: a later increment adds to it rather than
    # rebuilding a drained key.
    assert :ok = SlidingCounter.increment(sc, "k")
    assert 4 = SlidingCounter.count(sc, "k", 1_000)
  end