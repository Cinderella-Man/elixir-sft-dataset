  test "member seen in both an expired and a live bucket counts once", %{sc: sc} do
    # Time 0: u1 observed (will expire)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Time 600: u1 observed again (stays live)
    Clock.advance(600)
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Time 1_050: only the t=600 observation is in-window; union = {u1}
    Clock.advance(450)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end