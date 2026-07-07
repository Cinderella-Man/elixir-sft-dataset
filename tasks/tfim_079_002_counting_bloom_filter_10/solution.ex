  test "counters never go below zero" do
    filter =
      CountingBloomFilter.new(50, 0.01)
      |> CountingBloomFilter.add("x")

    filter = CountingBloomFilter.remove(filter, "x")
    # Removing again (now a non-member) must not underflow anything.
    filter = CountingBloomFilter.remove(filter, "x")

    for c <- Tuple.to_list(filter.counters) do
      assert c >= 0
    end
  end