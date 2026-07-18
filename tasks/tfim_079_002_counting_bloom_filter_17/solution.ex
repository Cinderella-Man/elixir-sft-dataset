  test "add/2 saturates counters at 255 and never overflows past it" do
    empty = CountingBloomFilter.new(50, 0.01)

    filter =
      Enum.reduce(1..400, empty, fn _i, f -> CountingBloomFilter.add(f, "hot") end)

    counters = Tuple.to_list(filter.counters)

    # The only item added is "hot", so its slots carry the largest counters:
    # they must have stopped climbing exactly at the 255 ceiling.
    assert Enum.max(counters) == 255
    assert Enum.all?(counters, fn c -> c <= 255 end)
    assert CountingBloomFilter.member?(filter, "hot")
  end