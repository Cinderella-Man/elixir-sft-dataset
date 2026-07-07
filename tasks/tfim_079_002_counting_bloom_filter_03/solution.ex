  test "new/2 scales m with expected size" do
    small = CountingBloomFilter.new(100, 0.01)
    large = CountingBloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end