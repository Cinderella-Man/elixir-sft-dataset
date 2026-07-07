  test "mixed term types are never false-negatives" do
    filter = ConcurrentBloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end