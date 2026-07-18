    test "decrement returns the new count" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.decrement(c) == 0
    end