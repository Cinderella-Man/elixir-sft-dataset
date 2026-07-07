  test "new/2 produces a struct with computed m and k and zero size" do
    filter = CountingBloomFilter.new(1_000, 0.01)

    assert filter.m > 0
    assert filter.k > 0
    assert CountingBloomFilter.count(filter) == 0

    loose = CountingBloomFilter.new(1_000, 0.10)
    tight = CountingBloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end