  test "member?/2 always true for added items (no false negatives)" do
    filter = CountingBloomFilter.new(500, 0.01)
    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &CountingBloomFilter.add(&2, &1))

    for item <- items do
      assert CountingBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member"
    end
  end