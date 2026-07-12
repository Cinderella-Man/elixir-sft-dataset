    test "tracks peak and started" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.increment(c) == 1
      assert ConcurrencyCounter.increment(c) == 2
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.peak(c) == 2
      assert ConcurrencyCounter.started(c) == 2
    end