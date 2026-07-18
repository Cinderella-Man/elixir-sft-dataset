  test "cleanup drops only the expired buckets of a key that is still live", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "k", "old")

    Clock.set(2_000)
    SlidingUniqueCounter.add(sc, "k", "new")

    send(sc, :cleanup)

    # The key survives, but "old" (bucket start 0, outside the 1_000ms horizon)
    # must be gone even when queried through a window wide enough to cover it.
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 100_000)
  end