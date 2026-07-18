  test "a member spread across two in-window buckets is unioned to one", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "u1")

    Clock.set(500)
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    # Buckets 0 and 5 are both in window at now=500; union = {"u1", "u2"}.
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end