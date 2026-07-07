  test "new/2 computes m and k and allocates an atomics-backed filter" do
    filter = ConcurrentBloomFilter.new(1_000, 0.01)
    assert filter.m > 0
    assert filter.k > 0

    loose = ConcurrentBloomFilter.new(1_000, 0.10)
    tight = ConcurrentBloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end