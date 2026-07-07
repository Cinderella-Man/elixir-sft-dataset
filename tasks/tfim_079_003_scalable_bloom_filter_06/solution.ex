  test "mixed term types survive growth without false negatives" do
    filter = ScalableBloomFilter.new(5, 0.01)
    items = [:a, :b, 1, 2, 3, {:x, 1}, {:y, 2}, "s1", "s2", "s3"]

    filter = Enum.reduce(items, filter, &ScalableBloomFilter.add(&2, &1))

    for item <- items do
      assert ScalableBloomFilter.member?(filter, item)
    end
  end