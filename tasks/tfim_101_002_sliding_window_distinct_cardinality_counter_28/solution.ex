  test "cleanup_interval_ms :infinity disables the periodic cleanup entirely" do
    {:ok, sc} = start_reporting_counter(cleanup_interval_ms: :infinity)

    SlidingUniqueCounter.add(sc, "k", "u1")
    flush_clock_reads()

    # Move the clock far past the retention horizon. With cleanup disabled the
    # process must never wake itself up, so no further clock read can arrive.
    Clock.advance(10_000)
    refute_receive {:clock_read, _}, 200

    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
  end