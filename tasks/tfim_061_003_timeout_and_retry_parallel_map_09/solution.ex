  test "never exceeds max_concurrency simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    RetryMap.pmap(1..8, fn _x ->
      ConcurrencyCounter.increment(counter)
      Process.sleep(60)
      ConcurrencyCounter.decrement(counter)
    end, max_concurrency: 3, timeout: 1000, max_attempts: 1)

    assert ConcurrencyCounter.peak(counter) <= 3
  end