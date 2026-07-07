  test "merge/2 with an empty filter leaves the other unchanged" do
    f1 = BloomFilter.new(100, 0.01)
    empty = BloomFilter.new(100, 0.01)

    f1 = Enum.reduce(["x", "y", "z"], f1, &BloomFilter.add(&2, &1))
    merged = BloomFilter.merge(f1, empty)

    assert BloomFilter.member?(merged, "x")
    assert BloomFilter.member?(merged, "y")
    assert BloomFilter.member?(merged, "z")
  end