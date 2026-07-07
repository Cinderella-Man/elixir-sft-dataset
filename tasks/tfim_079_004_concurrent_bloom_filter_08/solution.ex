  test "empty filter reports no members" do
    filter = ConcurrentBloomFilter.new(100, 0.01)
    refute ConcurrentBloomFilter.member?(filter, "ghost")
    refute ConcurrentBloomFilter.member?(filter, 0)
    refute ConcurrentBloomFilter.member?(filter, :nope)
  end