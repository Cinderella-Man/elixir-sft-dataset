  test "merge/2 is associative and idempotent on identical inputs" do
    a = BloomFilter.new(100, 0.01) |> BloomFilter.add("a-item")
    b = BloomFilter.new(100, 0.01) |> BloomFilter.add("b-item")
    c = BloomFilter.new(100, 0.01) |> BloomFilter.add({:c, 3})

    left = BloomFilter.merge(BloomFilter.merge(a, b), c)
    right = BloomFilter.merge(a, BloomFilter.merge(b, c))

    assert left == right
    assert BloomFilter.merge(a, a) == a
    assert BloomFilter.merge(left, left) == left
    assert BloomFilter.member?(left, "a-item")
    assert BloomFilter.member?(left, "b-item")
    assert BloomFilter.member?(left, {:c, 3})
  end