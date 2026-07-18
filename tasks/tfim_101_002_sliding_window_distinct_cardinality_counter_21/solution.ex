  test "cleanup fires on its own schedule without a directly sent :cleanup" do
    # The counter is given a clock that reports every read back to this test.
    # Once the test stops calling the server, any further clock read can only
    # come from the process waking itself up to run the periodic cleanup.
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: 20)

    SlidingUniqueCounter.add(sc, "k", "u1")
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1

    flush_clock_reads()
    Clock.advance(10_000)

    await_clock_read_at_least(10_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 0
  end