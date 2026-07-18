  test "new/2 accepts the smallest positive expected size (n = 1)" do
    filter = BloomFilter.new(1, 0.5)

    assert %BloomFilter{} = filter
    assert filter.m >= 1
    assert filter.k >= 1
    assert BloomFilter.member?(BloomFilter.add(filter, :only), :only)
  end