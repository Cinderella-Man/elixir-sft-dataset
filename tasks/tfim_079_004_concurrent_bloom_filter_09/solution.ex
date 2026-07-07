  test "merge/2 ORs the source into the target in place" do
    into = ConcurrentBloomFilter.new(200, 0.01)
    from = ConcurrentBloomFilter.new(200, 0.01)

    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(into, "a-#{i}") end)
    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(from, "b-#{i}") end)

    result = ConcurrentBloomFilter.merge(into, from)

    for i <- 1..100 do
      assert ConcurrentBloomFilter.member?(result, "a-#{i}")
      assert ConcurrentBloomFilter.member?(result, "b-#{i}")
    end

    # `into` was mutated in place and now also contains from's items.
    assert ConcurrentBloomFilter.member?(into, "b-1")
  end