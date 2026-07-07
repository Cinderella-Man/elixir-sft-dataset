  test "merge/2 is commutative" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(100, 0.01)

    f1 = BloomFilter.add(f1, "only-in-f1")
    f2 = BloomFilter.add(f2, "only-in-f2")

    m1 = BloomFilter.merge(f1, f2)
    m2 = BloomFilter.merge(f2, f1)

    assert BloomFilter.member?(m1, "only-in-f1")
    assert BloomFilter.member?(m1, "only-in-f2")
    assert BloomFilter.member?(m2, "only-in-f1")
    assert BloomFilter.member?(m2, "only-in-f2")

    # Bit arrays should be identical
    assert m1.bits == m2.bits
  end