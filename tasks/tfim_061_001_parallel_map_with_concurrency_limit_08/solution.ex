  test "actually runs tasks in parallel (peak > 1 with concurrency > 1)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..6,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 80)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    # With 6 items and max 3, we should reach at least 2 simultaneously
    assert ConcurrencyCounter.peak(counter) >= 2
  end