  test "member?/2 true for all added items (single process)" do
    filter = ConcurrentBloomFilter.new(500, 0.01)
    items = for i <- 1..500, do: "item-#{i}"
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end