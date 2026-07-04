  test "never exceeds max_concurrency simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    assert {:ok, _} =
             FailFastMap.pmap(1..10, fn _x ->
               ConcurrencyCounter.increment(counter)
               slow(:ok, 60)
               ConcurrencyCounter.decrement(counter)
             end, 3)

    assert ConcurrencyCounter.peak(counter) <= 3
  end