  test "a bucket starting exactly at the window threshold is counted", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # At now=1_000 with a 1_000ms window the threshold is exactly 0, and the
    # member's bucket starts at 0 — the comparison is `>=`, so it counts.
    Clock.set(1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end