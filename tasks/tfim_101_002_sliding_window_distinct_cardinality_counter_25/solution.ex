  test "counting works on the default monotonic clock when :clock is omitted" do
    {:ok, sc} = SlidingUniqueCounter.start_link(bucket_ms: 100, cleanup_interval_ms: :infinity)

    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 60_000)
  end