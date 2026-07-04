  test "never exceeds max_concurrency=3 simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..10,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 60)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    assert ConcurrencyCounter.peak(counter) <= 3
  end