  test "merge/2 contains all items from both filters" do
    f1 = BloomFilter.new(200, 0.01)
    f2 = BloomFilter.new(200, 0.01)

    f1 = Enum.reduce(1..100, f1, fn i, f -> BloomFilter.add(f, "a-#{i}") end)
    f2 = Enum.reduce(1..100, f2, fn i, f -> BloomFilter.add(f, "b-#{i}") end)

    merged = BloomFilter.merge(f1, f2)

    for i <- 1..100 do
      assert BloomFilter.member?(merged, "a-#{i}")
      assert BloomFilter.member?(merged, "b-#{i}")
    end
  end