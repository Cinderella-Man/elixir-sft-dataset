  test "periodic cleanup re-arms itself and purges data that expires later" do
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: 20)

    SlidingUniqueCounter.add(sc, "k1", "u1")
    flush_clock_reads()
    Clock.advance(10_000)

    await_clock_read_at_least(10_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0

    # Data added after that first purge must be reclaimed by a later cleanup,
    # which only happens if cleanup keeps re-scheduling itself.
    Clock.set(20_000)
    SlidingUniqueCounter.add(sc, "k2", "u2")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    flush_clock_reads()
    Clock.set(40_000)

    await_clock_read_at_least(40_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end