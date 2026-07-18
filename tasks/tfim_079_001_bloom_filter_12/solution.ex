  test "adding the same item multiple times has no extra effect" do
    f = BloomFilter.new(10, 0.01)
    f1 = BloomFilter.add(f, "dup")
    f2 = BloomFilter.add(f1, "dup")

    assert f1.bits == f2.bits
    assert BloomFilter.member?(f2, "dup")
  end