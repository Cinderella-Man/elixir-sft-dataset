  test "new/2 returns equal structs for repeated calls with identical arguments" do
    assert BloomFilter.new(1_000, 0.01) == BloomFilter.new(1_000, 0.01)
    assert BloomFilter.new(7, 0.25) == BloomFilter.new(7, 0.25)
    assert BloomFilter.new(1_000, 0.9) == BloomFilter.new(1_000, 0.9)
  end