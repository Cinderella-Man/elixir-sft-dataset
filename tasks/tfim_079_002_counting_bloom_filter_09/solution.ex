  test "remove/2 on a non-member is a no-op" do
    filter =
      CountingBloomFilter.new(100, 0.01)
      |> CountingBloomFilter.add("present")

    before_counters = filter.counters
    before_size = CountingBloomFilter.count(filter)

    filter = CountingBloomFilter.remove(filter, "absent")

    assert filter.counters == before_counters
    assert CountingBloomFilter.count(filter) == before_size
  end