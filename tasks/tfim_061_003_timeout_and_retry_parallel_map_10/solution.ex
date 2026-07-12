    test "starts at zero and tracks peak" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.peak(c) == 0
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.decrement(c)
      assert ConcurrencyCounter.peak(c) == 2
    end