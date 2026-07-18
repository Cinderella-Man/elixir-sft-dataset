  test ":name registers the process so the whole API is usable by name" do
    name = :"sliding_unique_counter_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      SlidingUniqueCounter.start_link(
        name: name,
        clock: &Clock.now/0,
        bucket_ms: 100,
        cleanup_interval_ms: :infinity,
        max_window_ms: 1_000
      )

    assert :ok = SlidingUniqueCounter.add(name, "k", "u1")
    assert :ok = SlidingUniqueCounter.add(name, "k", "u1")
    assert :ok = SlidingUniqueCounter.add(name, "k", "u2")

    assert 2 = SlidingUniqueCounter.distinct_count(name, "k", 1_000)
    assert SlidingUniqueCounter.tracked_key_count(name) == 1
  end