  test "new/2 produces a struct with computed m and k" do
    filter = BloomFilter.new(1_000, 0.01)

    # Optimal m for n=1000, p=0.01 is ~9585 bits; k is ~7
    assert filter.m > 0
    assert filter.k > 0

    # Sanity: tighter false-positive rate → larger bit array
    loose = BloomFilter.new(1_000, 0.10)
    tight = BloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end