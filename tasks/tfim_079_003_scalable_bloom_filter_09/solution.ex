  test "empty filter reports no members" do
    filter = ScalableBloomFilter.new(100, 0.01)
    refute ScalableBloomFilter.member?(filter, "ghost")
    refute ScalableBloomFilter.member?(filter, 123)
  end