  test "max_concurrency defaults to 5 when the option is omitted" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    RetryMap.pmap(
      1..12,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        Process.sleep(60)
        ConcurrencyCounter.decrement(counter)
      end,
      timeout: 2000
    )

    peak = ConcurrencyCounter.peak(counter)
    assert peak <= 5
    assert peak > 1
  end