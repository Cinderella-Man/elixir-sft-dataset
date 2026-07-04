  test "actually runs tasks in parallel" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    assert {:ok, _} =
             FailFastMap.pmap(1..6, fn _x ->
               ConcurrencyCounter.increment(counter)
               slow(:ok, 80)
               ConcurrencyCounter.decrement(counter)
             end, 3)

    assert ConcurrencyCounter.peak(counter) >= 2
  end