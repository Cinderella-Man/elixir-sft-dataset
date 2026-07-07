  test "mixed term types are never false-negatives" do
    filter = CountingBloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &CountingBloomFilter.add(&2, &1))

    for item <- items do
      assert CountingBloomFilter.member?(filter, item)
    end
  end