  test "new/2 with different expected sizes scales m accordingly" do
    small = BloomFilter.new(100, 0.01)
    large = BloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end