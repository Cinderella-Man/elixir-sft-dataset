  test "new/2 starts with exactly one slice and zero count" do
    filter = ScalableBloomFilter.new(100, 0.01)
    assert ScalableBloomFilter.num_slices(filter) == 1
    assert ScalableBloomFilter.count(filter) == 0
  end