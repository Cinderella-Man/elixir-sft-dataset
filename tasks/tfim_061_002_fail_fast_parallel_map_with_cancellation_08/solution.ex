  test "queued work is cancelled after a failure (not all elements started)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    result =
      FailFastMap.pmap(1..30, fn
        1 ->
          raise "boom"

        _x ->
          ConcurrencyCounter.increment(counter)
          slow(:ok, 200)
          ConcurrencyCounter.decrement(counter)
      end, 3)

    assert {:error, {0, _}} = result
    # Only the initial window (minus the failing element) could have started.
    assert ConcurrencyCounter.started(counter) < 30
  end