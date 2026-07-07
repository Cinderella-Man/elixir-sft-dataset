  test "empty filter reports no members" do
    filter = BloomFilter.new(100, 0.01)

    refute BloomFilter.member?(filter, "ghost")
    refute BloomFilter.member?(filter, 0)
    refute BloomFilter.member?(filter, :nope)
  end