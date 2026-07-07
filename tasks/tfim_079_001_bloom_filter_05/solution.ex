  test "atoms, integers, and tuples are never false-negatives" do
    filter = BloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item)
    end
  end