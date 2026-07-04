  test "max_concurrency=1 never exceeds 1 simultaneous task" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..5,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 30)
        ConcurrencyCounter.decrement(counter)
      end,
      1
    )

    assert ConcurrencyCounter.peak(counter) == 1
  end